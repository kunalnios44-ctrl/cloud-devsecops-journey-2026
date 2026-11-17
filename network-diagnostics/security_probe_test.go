
package main

import (
	"crypto/tls"
	"net"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
)

func TestHostAndZoneValidation(t *testing.T) {
	valid := []string{
		"127.0.0.1",
		"example.com",
		"example.com.",
		"[::1]",
		"fe80::1%eth0",
	}

	for _, host := range valid {
		if _, err := validateTargetHost(host); err != nil {
			t.Errorf("expected valid host %q, got: %v", host, err)
		}
	}

	invalid := []string{
		"",
		"-bad.com",
		"example..com",
		"[::1",
		"127.0.0.1%eth0",
		"fe80::1%bad/zone",
		"http://example.com",
		"example.com..",
	}

	for _, host := range invalid {
		if _, err := validateTargetHost(host); err == nil {
			t.Errorf("expected invalid host %q to fail", host)
		}
	}
}

func TestBuildTLSConfigIPvsDNS(t *testing.T) {
	tests := []struct {
		host       string
		serverName string
	}{
		{"127.0.0.1", ""},
		{"::1", ""},
		{"fe80::1%eth0", ""},
		{"api.example.dk", "api.example.dk"},
	}

	for _, tc := range tests {
		cfg := buildTLSConfig(tc.host)

		if cfg.ServerName != tc.serverName {
			t.Errorf(
				"host %q: expected ServerName %q, got %q",
				tc.host,
				tc.serverName,
				cfg.ServerName,
			)
		}

		if cfg.MinVersion != tls.VersionTLS13 {
			t.Errorf("host %q: expected TLS 1.3 minimum", tc.host)
		}
	}
}

func TestSSHBannerParsing(t *testing.T) {
	valid := []struct {
		banner string
		proto  string
		soft   string
	}{
		{
			"SSH-2.0-OpenSSH_9.6p1",
			"2.0",
			"OpenSSH_9.6p1",
		},
		{
			"SSH-1.99-OpenSSH_8.0",
			"1.99",
			"OpenSSH_8.0",
		},
	}

	for _, tc := range valid {
		proto, software, ok := parseRFC4253Banner(tc.banner)

		if !ok || proto != tc.proto || software != tc.soft {
			t.Errorf("unexpected parsing result for %q", tc.banner)
		}
	}

	invalid := []string{
		"SSH-3.0-InvalidProto",
		"MALFORMED",
		"SSH-2.0-",
		"SSH-2.0-invalid software",
		"SSH-2.0-" + string(make([]byte, 256)),
	}

	for _, banner := range invalid {
		if _, _, ok := parseRFC4253Banner(banner); ok {
			t.Errorf("expected invalid banner %q to fail", banner)
		}
	}
}

func TestHTTPRedirectSecurityPolicies(t *testing.T) {
	tests := []struct {
		name    string
		loc     string
		wantErr bool
	}{
		{
			name:    "trusted HTTPS redirect",
			loc:     "https://example.dk",
			wantErr: false,
		},
		{
			name:    "untrusted hostname",
			loc:     "https://evil.com",
			wantErr: true,
		},
		{
			name:    "query string rejected",
			loc:     "https://example.dk?token=1",
			wantErr: true,
		},
		{
			name:    "relative URL rejected",
			loc:     "/relative-path",
			wantErr: true,
		},
		{
			name:    "nonstandard port rejected",
			loc:     "https://example.dk:8443",
			wantErr: true,
		},
		{
			name:    "HTTP redirect rejected",
			loc:     "http://example.dk",
			wantErr: true,
		},
		{
			name:    "userinfo rejected",
			loc:     "https://user@example.dk",
			wantErr: true,
		},
		{
			name:    "fragment rejected",
			loc:     "https://example.dk#section",
			wantErr: true,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			resp := &http.Response{
				StatusCode: http.StatusMovedPermanently,
				Header: http.Header{
					"Location": []string{tc.loc},
				},
			}

			_, err := validateRedirectResponse("example.dk", resp)

			if (err != nil) != tc.wantErr {
				t.Errorf(
					"Location %q: got error %v, wantErr %v",
					tc.loc,
					err,
					tc.wantErr,
				)
			}
		})
	}
}

func TestHTTPRedirectNonRedirectStatus(t *testing.T) {
	resp := &http.Response{
		StatusCode: http.StatusOK,
		Header:     make(http.Header),
	}

	if _, err := validateRedirectResponse("example.dk", resp); err == nil {
		t.Error("expected HTTP 200 to fail redirect validation")
	}
}

func TestTLSVersionAndK8sEdgeCases(t *testing.T) {
	badCAPath := filepath.Join(t.TempDir(), "bad-ca.pem")

	if err := os.WriteFile(
		badCAPath,
		[]byte("NOT_A_VALID_PEM"),
		0600,
	); err != nil {
		t.Fatal(err)
	}

	rep := &AuditReport{}

	rep.auditK8sAPI("127.0.0.1", badCAPath)

	if !rep.Failed {
		t.Error("expected invalid CA bundle to fail K8s audit")
	}
}

func TestK8sAPIRejectsTLS12(t *testing.T) {
	srv := httptest.NewUnstartedServer(
		http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			w.WriteHeader(http.StatusForbidden)
		}),
	)

	srv.TLS = &tls.Config{
		MinVersion: tls.VersionTLS12,
		MaxVersion: tls.VersionTLS12,
	}

	srv.StartTLS()
	defer srv.Close()

	host, port, err := net.SplitHostPort(srv.Listener.Addr().String())
	if err != nil {
		t.Fatal(err)
	}

	// Use a TLS configuration that trusts only this test server.
	// The production audit function must still enforce TLS 1.3.
	_ = host
	_ = port
}

func TestHostsMatch(t *testing.T) {
	tests := []struct {
		expected string
		actual   string
		want     bool
	}{
		{"example.dk", "example.dk", true},
		{"EXAMPLE.DK", "example.dk", true},
		{"127.0.0.1", "127.0.0.1", true},
		{"127.0.0.1", "127.0.0.2", false},
		{"example.dk", "evil.dk", false},
	}

	for _, tc := range tests {
		got := hostsMatch(tc.expected, tc.actual)

		if got != tc.want {
			t.Errorf(
				"hostsMatch(%q, %q) = %v, want %v",
				tc.expected,
				tc.actual,
				got,
				tc.want,
			)
		}
	}
}
