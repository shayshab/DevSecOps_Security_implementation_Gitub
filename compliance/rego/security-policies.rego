package security.policies

# Security Policy: Container Security
container_security {
    # Check if container runs as non-root user
    input.container.security_context.run_as_non_root == true
    
    # Check if container has read-only root filesystem
    input.container.security_context.read_only_root_filesystem == true
    
    # Check if container drops unnecessary capabilities
    input.container.security_context.capabilities.drop[_] == "ALL"
}

# Security Policy: Network Security
network_security {
    # Check if pod has network policy
    input.network_policy != null
    
    # Check if ingress is restricted
    input.network_policy.spec.policy_types[_] == "Ingress"
    
    # Check if egress is restricted
    input.network_policy.spec.policy_types[_] == "Egress"
}

# Security Policy: Resource Limits
resource_limits {
    # Check if CPU limits are set
    input.container.resources.limits.cpu != null
    
    # Check if memory limits are set
    input.container.resources.limits.memory != null
    
    # Check if CPU requests are set
    input.container.resources.requests.cpu != null
    
    # Check if memory requests are set
    input.container.resources.requests.memory != null
}

# Security Policy: Secrets Management
secrets_management {
    # Check if secrets are not hardcoded
    not input.container.env[_].value
    
    # Check if secrets use secret references
    input.container.env[_].value_from.secret_key_ref
}

# Security Policy: Image Security
image_security {
    # Check if image has digest
    input.container.image =~ ".*@sha256:.*"
    
    # Check if image is from trusted registry
    input.container.image =~ ".*\\.azurecr\\.io/.*|.*\\.ecr\\.amazonaws\\.com/.*|.*\\.gcr\\.io/.*"
}

# Security Policy: Pod Security Standards
pod_security_standards {
    # Check if pod security context is set
    input.pod.security_context != null
    
    # Check if pod runs as non-root
    input.pod.security_context.run_as_non_root == true
    
    # Check if pod has security context
    input.pod.security_context.fs_group != null
}

# Security Policy: RBAC
rbac_compliance {
    # Check if service account is specified
    input.service_account_name != ""
    
    # Check if RBAC is enabled
    input.automount_service_account_token == false
}

# Security Policy: Audit Logging
audit_logging {
    # Check if audit logging is enabled
    input.audit.enabled == true
    
    # Check if audit policy is configured
    input.audit.policy != null
}

# Security Policy: Encryption
encryption_compliance {
    # Check if data at rest is encrypted
    input.storage.encryption.enabled == true
    
    # Check if data in transit is encrypted
    input.network.tls.enabled == true
}

# Security Policy: Vulnerability Scanning
vulnerability_scanning {
    # Check if vulnerability scan passed
    input.security_scan.status == "PASSED"
    
    # Check if no critical vulnerabilities
    input.security_scan.critical_count == 0
    
    # Check if no high vulnerabilities
    input.security_scan.high_count == 0
}

# Security Policy: Compliance Score
compliance_score {
    score := count([
        container_security,
        network_security,
        resource_limits,
        secrets_management,
        image_security,
        pod_security_standards,
        rbac_compliance,
        audit_logging,
        encryption_compliance,
        vulnerability_scanning
    ])
    
    score >= 8  # Require 80% compliance
}
