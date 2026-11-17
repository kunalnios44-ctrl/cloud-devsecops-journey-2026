
func main() {
	rawHost := flag.String(
		"host",
		"127.0.0.1",
		"Target IPv4/IPv6/Hostname",
	)

	k8sCA := flag.String(
		"k8s-ca",
		"",
		"Path to Kubernetes cluster CA PEM",
	)

	allowSSH := flag.Bool(
		"allow-ssh",
		false,
		"Allow RFC-4253 SSH-2.0 exposure",
	)

	flag.Parse()

	host, err := validateTargetHost(*rawHost)

	if err != nil {
		fmt.Printf("[FAIL] Input Validation: %v\n", err)
		os.Exit(1)
	}

	rep := &AuditReport{}

	fmt.Printf(
		"=== Strict Zero-Trust External Network Probe | Target: %s ===\n",
		host,
	)

	rep.auditSSH(host, *allowSSH)
	rep.auditHTTP(host)
	rep.auditTLS(host)
	rep.auditK8sAPI(host, *k8sCA)

	// Exit Code 1: Security policy violation.
	if rep.Failed {
		fmt.Println(
			"=== RESULT: FAIL (Security policy violations detected) ===",
		)
		os.Exit(1)
	}

	// Exit Code 2: One or more checks incomplete.
	if rep.Incomplete > 0 {
		fmt.Printf(
			"=== RESULT: INCONCLUSIVE (%d incomplete endpoint checks) ===\n",
			rep.Incomplete,
		)
		os.Exit(2)
	}

	// Exit Code 0: All four endpoint checks passed.
	fmt.Println(
		"=== RESULT: PASS (All four endpoint checks passed) ===",
	)
	os.Exit(0)
}
