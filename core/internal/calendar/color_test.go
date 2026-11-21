package calendar

import "testing"

func TestNormalizeColor(t *testing.T) {
	cases := []struct {
		in   string
		want string
	}{
		{"#0B8043", "#0b8043"},
		{"0b8043", "#0b8043"},
		{"#abc", "#abc"},
		{"#FF2968FF", "#ff2968"},
		{"#AAAABBBBCCCC", "#aabbcc"},
		{" #ff0000 ", "#ff0000"},
		{"DarkSlateBlue", "darkslateblue"},
		{"", ""},
		{"#", ""},
		{"#12345", ""},
		{"#gg0000", ""},
		{"rgb(1,2,3)", ""},
		{"not a color", ""},
	}
	for _, c := range cases {
		if got := NormalizeColor(c.in); got != c.want {
			t.Errorf("NormalizeColor(%q) = %q, want %q", c.in, got, c.want)
		}
	}
}
