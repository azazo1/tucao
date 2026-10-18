package api

import (
	"bytes"
	"context"
	"encoding/json"
	"net/url"
	"strings"

	"github.com/azazo1/tucao/cli/internal/model"
)

// rawReply 是评论接口返回的结构.
type rawReply struct {
	ID        FlexString `json:"id"`
	CommentID FlexString `json:"commentid"`
	UserID    FlexInt    `json:"userid"`
	UserName  FlexString `json:"username"`
	Nickname  FlexString `json:"nickname"`
	Content   FlexString `json:"content"`
	Avatar    FlexString `json:"avatar"`
	CreateAt  FlexString `json:"creat_at"`
	Support   FlexInt    `json:"support"`
	Replys    FlexInt    `json:"replys"`
	ReplyID   FlexInt    `json:"replyid"`
	ReplyUID  FlexInt    `json:"replyuid"`
	RUserName FlexString `json:"rusername"`
	Replies   []rawReply `json:"replies"`
}

func (r rawReply) toModel() model.Reply {
	name := r.Nickname.String()
	if name == "" {
		name = r.UserName.String()
	}
	reply := model.Reply{
		ID:            r.ID.String(),
		UserID:        r.UserID.Int(),
		UserName:      name,
		Content:       r.Content.String(),
		Avatar:        r.Avatar.String(),
		CreateAt:      r.CreateAt.String(),
		Support:       r.Support.Int(),
		ReplyCount:    r.Replys.Int(),
		ReplyID:       r.ReplyID.Int(),
		ReplyUserID:   r.ReplyUID.Int(),
		ReplyUserName: r.RUserName.String(),
	}
	for _, child := range r.Replies {
		reply.Replies = append(reply.Replies, child.toModel())
	}
	return reply
}

// parseReplyPayload 解析评论响应.
//
// 站点的 data 有时是对象 (键是评论 id), 有时是数组; 用流式解码可以
// 保持对象里的原始顺序, 不会因为 map 无序把楼层顺序打乱.
func parseReplyPayload(raw []byte) ([]rawReply, int, string, error) {
	text := strings.TrimSpace(strings.TrimPrefix(string(raw), "\ufeff"))
	if text == "" || text == "0" {
		return nil, 0, "", nil
	}
	var payload struct {
		Total FlexInt         `json:"total"`
		Title FlexString      `json:"title"`
		Data  json.RawMessage `json:"data"`
	}
	if err := json.Unmarshal([]byte(text), &payload); err != nil {
		return nil, 0, "", WrapError(CodeUpstream, "解析评论", "评论内容无法解析", err)
	}
	items, err := decodeReplyData(payload.Data)
	if err != nil {
		return nil, 0, "", err
	}
	return items, payload.Total.Int(), payload.Title.String(), nil
}

func decodeReplyData(raw json.RawMessage) ([]rawReply, error) {
	trimmed := bytes.TrimSpace(raw)
	if len(trimmed) == 0 || string(trimmed) == "null" {
		return nil, nil
	}
	switch trimmed[0] {
	case '[':
		var items []rawReply
		if err := json.Unmarshal(trimmed, &items); err != nil {
			return nil, WrapError(CodeUpstream, "解析评论", "评论列表无法解析", err)
		}
		return items, nil
	case '{':
		decoder := json.NewDecoder(bytes.NewReader(trimmed))
		if _, err := decoder.Token(); err != nil {
			return nil, WrapError(CodeUpstream, "解析评论", "评论列表无法解析", err)
		}
		items := []rawReply{}
		for decoder.More() {
			if _, err := decoder.Token(); err != nil {
				return nil, WrapError(CodeUpstream, "解析评论", "评论列表无法解析", err)
			}
			var item rawReply
			if err := decoder.Decode(&item); err != nil {
				return nil, WrapError(CodeUpstream, "解析评论", "评论列表无法解析", err)
			}
			items = append(items, item)
		}
		return items, nil
	default:
		return nil, nil
	}
}

// ReplyList 拉取评论.
//
// replyID 不为 0 时拉取该评论下的楼中楼回复.
func (c *Client) ReplyList(ctx context.Context, typeID int, hid string, page, pageSize, replyID int) (*model.ReplyThread, error) {
	path, query := IndexPath("comment", "index", "ajax", buildQuery(
		"commentid", CommentID(typeID, hid),
		"replyid", replyID,
		"page", page,
		"num", pageSize,
	))
	raw, err := c.Get(ctx, c.SiteURL(path), query)
	if err != nil {
		return nil, err
	}
	items, total, title, err := parseReplyPayload(raw)
	if err != nil {
		return nil, err
	}
	thread := &model.ReplyThread{
		Total:    total,
		Page:     page,
		PageSize: pageSize,
		Title:    title,
		Items:    make([]model.Reply, 0, len(items)),
	}
	for _, item := range items {
		thread.Items = append(thread.Items, item.toModel())
	}
	if thread.Total == 0 {
		thread.Total = len(thread.Items)
	}
	return thread, nil
}

// ReplyCount 取评论总数, 只拉一条省流量.
func (c *Client) ReplyCount(ctx context.Context, typeID int, hid string) (int, error) {
	thread, err := c.ReplyList(ctx, typeID, hid, 1, 1, 0)
	if err != nil {
		return 0, err
	}
	return thread.Total, nil
}

// ReplySend 发送评论或回复.
//
// 参数位置与官方一致: commentid, id 与 replyuid 是查询参数,
// 只有 content 是表单字段. replyID 为 0 表示发顶层评论,
// 不为 0 时 replyUID 必须是被回复者的 uid, 否则站点会拒收.
func (c *Client) ReplySend(ctx context.Context, typeID int, hid, content string, replyID, replyUID int) (string, error) {
	path, query := IndexPath("comment", "index", "post", buildQuery(
		"commentid", CommentID(typeID, hid),
		"id", replyID,
		"replyuid", replyUID,
	))
	form := url.Values{}
	form.Set("content", content)
	raw, err := c.PostForm(ctx, c.SiteURL(path), query, form)
	if err != nil {
		return "", err
	}
	return string(raw), nil
}

// ReplySupport 点赞评论.
func (c *Client) ReplySupport(ctx context.Context, commentID, replyID string) (string, error) {
	path, query := IndexPath("comment", "index", "support", buildQuery(
		"commentid", commentID,
		"id", replyID,
		"format", "json",
	))
	raw, err := c.Get(ctx, c.SiteURL(path), query)
	if err != nil {
		return "", err
	}
	return string(raw), nil
}
