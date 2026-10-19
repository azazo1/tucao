package api

import "testing"

func TestIsPlaceholderImage(t *testing.T) {
	placeholders := []string{
		"/statics/images/nopic.gif",
		"https://www.tucao.my/statics/images/nopic.gif",
		"https://www.tucao.my/statics/images/nopic.gif?v=2",
		"https://www.tucao.my/statics/images/NOPIC.GIF",
	}
	for _, source := range placeholders {
		if !IsPlaceholderImage(source) {
			t.Fatalf("IsPlaceholderImage(%q) 应当为真", source)
		}
	}
	realImages := []string{
		"",
		"https://www.tucao.my/uploadfile/2023/0822/20230822065236713.jpg",
		"/uploadfile/2023/0906/20230906101938854.png",
		"https://www.tucao.my/phpsso_server/uploadfile/avatar/46/4/453520/180x180.jpg",
	}
	for _, source := range realImages {
		if IsPlaceholderImage(source) {
			t.Fatalf("IsPlaceholderImage(%q) 应当为假", source)
		}
	}
}
