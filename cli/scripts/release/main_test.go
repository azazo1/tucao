package main

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// initRepo 建一个临时 git 仓库, 用于版本解析测试.
func initRepo(t *testing.T) string {
	t.Helper()
	if _, err := exec.LookPath("git"); err != nil {
		t.Skip("环境里没有 git")
	}
	dir := t.TempDir()
	runGit(t, dir, "init", "-q", "-b", "main")
	runGit(t, dir, "config", "user.email", "test@example.com")
	runGit(t, dir, "config", "user.name", "tester")
	runGit(t, dir, "config", "commit.gpgsign", "false")
	runGit(t, dir, "config", "tag.gpgsign", "false")
	return dir
}

func runGit(t *testing.T, dir string, args ...string) {
	t.Helper()
	command := exec.Command("git", args...)
	command.Dir = dir
	if output, err := command.CombinedOutput(); err != nil {
		t.Fatalf("git %s 失败: %v %s", strings.Join(args, " "), err, output)
	}
}

func commit(t *testing.T, dir, content string) {
	t.Helper()
	if err := os.WriteFile(filepath.Join(dir, "a.txt"), []byte(content), 0o644); err != nil {
		t.Fatalf("写文件失败: %v", err)
	}
	runGit(t, dir, "add", ".")
	runGit(t, dir, "commit", "-q", "-m", "提交 "+content)
}

func TestGitVersionIgnoresRollingTag(t *testing.T) {
	dir := initRepo(t)
	commit(t, dir, "1")
	// 版本 tag 与安卓端一致, 用附注 tag.
	runGit(t, dir, "tag", "-a", "v1.0.0", "-m", "v1.0.0")
	commit(t, dir, "2")
	// 预发布用的滚动 tag 是轻量 tag, 而且名字不带版本前缀.
	runGit(t, dir, "tag", "dev-latest")

	tag, describe, err := gitVersionIn(dir)
	if err != nil {
		t.Fatalf("解析版本失败: %v", err)
	}
	if tag != "v1.0.0" {
		t.Fatalf("滚动 tag 被当成了版本 tag: %s", tag)
	}
	if !strings.HasPrefix(describe, "v1.0.0-1-g") {
		t.Fatalf("版本描述不正确: %s", describe)
	}
}

func TestGitVersionWithoutVersionTag(t *testing.T) {
	dir := initRepo(t)
	commit(t, dir, "1")
	// 只有滚动 tag 时不该把它当版本.
	runGit(t, dir, "tag", "dev-latest")
	tag, describe, err := gitVersionIn(dir)
	if err != nil {
		t.Fatalf("解析版本失败: %v", err)
	}
	if tag != "devel" || describe != "devel" {
		t.Fatalf("没有版本 tag 时应回落到 devel: %s %s", tag, describe)
	}

	// 名字像版本但不符合 semver 的 tag 也不能用.
	runGit(t, dir, "tag", "-a", "v-next", "-m", "v-next")
	tag, describe, err = gitVersionIn(dir)
	if err != nil {
		t.Fatalf("解析版本失败: %v", err)
	}
	if tag != "devel" || describe != "devel" {
		t.Fatalf("非法版本 tag 应被忽略: %s %s", tag, describe)
	}
}

func TestGitVersionOnTagCommit(t *testing.T) {
	dir := initRepo(t)
	commit(t, dir, "1")
	runGit(t, dir, "tag", "-a", "v2.1.3", "-m", "v2.1.3")
	tag, describe, err := gitVersionIn(dir)
	if err != nil {
		t.Fatalf("解析版本失败: %v", err)
	}
	if tag != "v2.1.3" || describe != "v2.1.3" {
		t.Fatalf("正好在 tag 上时应只有版本号: %s %s", tag, describe)
	}
}

func TestResolveMetadataNames(t *testing.T) {
	cases := []struct {
		goos, goarch  string
		release       string
		wantArchive   string
		wantBinaryEnd string
	}{
		{"darwin", "arm64", "1.3.0", "tucao-cli-1.3.0-macos-aarch64.tar.gz", "bin/tucao"},
		{"linux", "amd64", "1.3.0", "tucao-cli-1.3.0-linux-x86_64.tar.gz", "bin/tucao"},
		{"windows", "amd64", "1.3.0", "tucao-cli-1.3.0-windows-x86_64.zip", "bin/tucao.exe"},
		{"linux", "arm64", "1.3.0-7e33cd3", "tucao-cli-1.3.0-7e33cd3-linux-aarch64.tar.gz", "bin/tucao"},
	}
	for _, testCase := range cases {
		resolved, err := resolveTarget(testCase.goos, testCase.goarch)
		if err != nil {
			t.Fatalf("解析目标失败: %v", err)
		}
		t.Setenv("TUCAO_BUILD_VERSION", testCase.release)
		t.Setenv("TUCAO_RELEASE_VERSION", testCase.release)
		build, err := resolveMetadata(resolved)
		if err != nil {
			t.Fatalf("解析产物失败: %v", err)
		}
		if filepath.Base(build.ArchivePath) != testCase.wantArchive {
			t.Fatalf("归档名为 %s, 期望 %s", filepath.Base(build.ArchivePath), testCase.wantArchive)
		}
		if filepath.ToSlash(build.BinaryPath) != testCase.wantBinaryEnd {
			t.Fatalf("二进制路径为 %s, 期望 %s", build.BinaryPath, testCase.wantBinaryEnd)
		}
	}
}

func TestResolveMetadataRejectsBadVersion(t *testing.T) {
	resolved, err := resolveTarget("linux", "amd64")
	if err != nil {
		t.Fatalf("解析目标失败: %v", err)
	}
	t.Setenv("TUCAO_BUILD_VERSION", "1.3.0")
	t.Setenv("TUCAO_RELEASE_VERSION", "1.3.0/../bad")
	if _, err := resolveMetadata(resolved); err == nil {
		t.Fatal("含非法字符的版本号应当被拒绝")
	}
}

func TestResolveTargetRejectsUnknownPlatform(t *testing.T) {
	for _, spec := range [][2]string{{"plan9", "amd64"}, {"linux", "riscv64"}} {
		if _, err := resolveTarget(spec[0], spec[1]); err == nil {
			t.Fatalf("不支持的目标应当报错: %s/%s", spec[0], spec[1])
		}
	}
}

func TestSanitizeVersion(t *testing.T) {
	cases := map[string]string{
		"v1.3.0-5-g915a96e":       "v1.3.0-5-g915a96e",
		"v1.3.0-5-g915a96e-dirty": "v1.3.0-5-g915a96e-dirty",
		"  v1.3.0  ":              "v1.3.0",
		"":                        "devel",
		"v1.3.0 beta":             "v1.3.0.beta",
	}
	for raw, want := range cases {
		if got := sanitizeVersion(raw); got != want {
			t.Fatalf("sanitizeVersion(%q) = %q, 期望 %q", raw, got, want)
		}
	}
}
