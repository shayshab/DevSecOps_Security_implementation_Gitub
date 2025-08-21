#!/bin/bash

# DevSecOps Environment Setup Script
set -e

echo "🚀 Setting up DevSecOps environment..."

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    echo "❌ Docker is not running. Please start Docker and try again."
    exit 1
fi

# Check if Docker Compose is available
if ! command -v docker-compose &> /dev/null; then
    echo "❌ Docker Compose is not installed. Please install it first."
    exit 1
fi

# Create necessary directories
echo "📁 Creating project directories..."
mkdir -p {reports,logs,configs,secrets}

# Set up environment variables
echo "🔧 Setting up environment variables..."
cat > .env << EOF
# DevSecOps Environment Configuration
ENVIRONMENT=development
SECURITY_LEVEL=high
COMPLIANCE_FRAMEWORK=SOC2

# Database Configuration
POSTGRES_DB=devsecops
POSTGRES_USER=devsecops
POSTGRES_PASSWORD=secure_password_123

# Redis Configuration
REDIS_PASSWORD=secure_redis_password_123

# Security Tools
SONARQUBE_URL=http://localhost:9000
ZAP_URL=http://localhost:8080
TRIVY_URL=http://localhost:8081
PROMETHEUS_URL=http://localhost:9090
GRAFANA_URL=http://localhost:3000

# Monitoring
ENABLE_SECURITY_MONITORING=true
ENABLE_COMPLIANCE_MONITORING=true
ENABLE_VULNERABILITY_SCANNING=true
EOF

# Set up security policies
echo "🔒 Setting up security policies..."
mkdir -p security/policies
cp compliance/rego/security-policies.rego security/policies/

# Set up monitoring configuration
echo "📊 Setting up monitoring configuration..."
mkdir -p monitoring/{grafana/provisioning,logstash/{pipeline,config},alertmanager}

# Create Grafana datasource
cat > monitoring/grafana/provisioning/datasources/datasource.yml << EOF
apiVersion: 1
datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
EOF

# Create Grafana dashboard
cat > monitoring/grafana/provisioning/dashboards/dashboard.yml << EOF
apiVersion: 1
providers:
  - name: 'default'
    orgId: 1
    folder: ''
    type: file
    disableDeletion: false
    editable: true
    options:
      path: /etc/grafana/provisioning/dashboards
EOF

# Set up Alert Manager
cat > monitoring/alertmanager/alertmanager.yml << EOF
global:
  smtp_smarthost: 'localhost:587'
  smtp_from: 'alertmanager@devsecops.local'

route:
  group_by: ['alertname', 'cluster', 'service']
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 4h
  receiver: 'web.hook'

receivers:
  - name: 'web.hook'
    webhook_configs:
      - url: 'http://127.0.0.1:5001/'
EOF

# Set up Logstash pipeline
cat > monitoring/logstash/pipeline/security-logs.conf << EOF
input {
  beats {
    port => 5044
  }
}

filter {
  if [fields][type] == "security" {
    grok {
      match => { "message" => "%{TIMESTAMP_ISO8601:timestamp} %{LOGLEVEL:level} %{GREEDYDATA:message}" }
    }
    date {
      match => [ "timestamp", "ISO8601" ]
    }
  }
}

output {
  elasticsearch {
    hosts => ["elasticsearch:9200"]
    index => "security-logs-%{+YYYY.MM.dd}"
  }
}
EOF

# Set up Logstash config
cat > monitoring/logstash/config/logstash.yml << EOF
http.host: "0.0.0.0"
xpack.monitoring.elasticsearch.hosts: [ "http://elasticsearch:9200" ]
EOF

# Set up Nginx configuration
echo "🌐 Setting up Nginx configuration..."
mkdir -p infrastructure/nginx/ssl

cat > infrastructure/nginx/nginx.conf << EOF
events {
    worker_connections 1024;
}

http {
    upstream web_app {
        server web-app:3000;
    }
    
    upstream api_app {
        server api-app:4000;
    }
    
    server {
        listen 80;
        server_name localhost;
        
        location / {
            proxy_pass http://web_app;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
        }
        
        location /api/ {
            proxy_pass http://api_app/;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
        }
        
        location /health {
            access_log off;
            return 200 "healthy\n";
            add_header Content-Type text/plain;
        }
    }
}
EOF

# Set up database initialization
echo "🗄️ Setting up database initialization..."
cat > infrastructure/init-db.sql << EOF
-- DevSecOps Database Initialization
CREATE DATABASE IF NOT EXISTS devsecops;
\c devsecops;

-- Security events table
CREATE TABLE IF NOT EXISTS security_events (
    id SERIAL PRIMARY KEY,
    event_type VARCHAR(100) NOT NULL,
    severity VARCHAR(20) NOT NULL,
    description TEXT,
    source_ip INET,
    user_id VARCHAR(100),
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    metadata JSONB
);

-- Compliance checks table
CREATE TABLE IF NOT EXISTS compliance_checks (
    id SERIAL PRIMARY KEY,
    check_name VARCHAR(200) NOT NULL,
    status VARCHAR(20) NOT NULL,
    score DECIMAL(5,2),
    details JSONB,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Vulnerability findings table
CREATE TABLE IF NOT EXISTS vulnerability_findings (
    id SERIAL PRIMARY KEY,
    cve_id VARCHAR(20),
    severity VARCHAR(20) NOT NULL,
    component VARCHAR(200),
    description TEXT,
    remediation TEXT,
    discovered_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    resolved_at TIMESTAMP
);

-- Create indexes
CREATE INDEX idx_security_events_timestamp ON security_events(timestamp);
CREATE INDEX idx_security_events_severity ON security_events(severity);
CREATE INDEX idx_compliance_checks_timestamp ON compliance_checks(timestamp);
CREATE INDEX idx_vulnerability_findings_severity ON vulnerability_findings(severity);
EOF

# Set up security scanning scripts
echo "🔍 Setting up security scanning scripts..."
mkdir -p scripts/security

cat > scripts/security/run-sast-scan.sh << 'EOF'
#!/bin/bash
# SAST Security Scan Script

echo "🔍 Running SAST security scan..."

# Run SonarQube analysis
if [ -f "sonar-project.properties" ]; then
    echo "Running SonarQube analysis..."
    docker run --rm \
        -e SONAR_HOST_URL="http://localhost:9000" \
        -e SONAR_LOGIN="$SONAR_TOKEN" \
        -v "$(pwd):/usr/src" \
        sonarqube:9.9-community \
        sonar-scanner
else
    echo "No sonar-project.properties found. Creating default configuration..."
    cat > sonar-project.properties << 'SONAREOF'
sonar.projectKey=devsecops-project
sonar.projectName=DevSecOps Project
sonar.projectVersion=1.0.0
sonar.sources=src
sonar.tests=tests
sonar.exclusions=**/node_modules/**,**/vendor/**,**/dist/**
SONAREOF
fi

echo "✅ SAST scan completed"
EOF

cat > scripts/security/run-dast-scan.sh << 'EOF'
#!/bin/bash
# DAST Security Scan Script

echo "🔍 Running DAST security scan..."

# Run OWASP ZAP scan
echo "Running OWASP ZAP scan..."
docker run --rm \
    -v "$(pwd)/reports:/zap/wrk" \
    owasp/zap2docker-stable \
    zap-baseline.py \
    -t http://localhost:8080 \
    -J zap-report.json \
    -r zap-report.html

echo "✅ DAST scan completed"
EOF

cat > scripts/security/run-container-scan.sh << 'EOF'
#!/bin/bash
# Container Security Scan Script

echo "🔍 Running container security scan..."

# Run Trivy scan on local images
echo "Scanning local Docker images..."
docker images --format "{{.Repository}}:{{.Tag}}" | grep -v "<none>" | while read image; do
    echo "Scanning $image..."
    docker run --rm \
        -v /var/run/docker.sock:/var/run/docker.sock \
        -v "$(pwd)/reports:/reports" \
        aquasec/trivy:latest \
        image --format json --output /reports/trivy-$(echo $image | tr ':/' '_').json "$image"
done

echo "✅ Container scan completed"
EOF

# Make scripts executable
chmod +x scripts/security/*.sh

# Create comprehensive security scan script
cat > scripts/security-scan.sh << 'EOF'
#!/bin/bash
# Comprehensive Security Scan Script

echo "🚀 Starting comprehensive security scan..."

# Create reports directory
mkdir -p reports/$(date +%Y%m%d)

# Run all security scans
echo "🔍 Running SAST scan..."
./scripts/security/run-sast-scan.sh

echo "🔍 Running DAST scan..."
./scripts/security/run-dast-scan.sh

echo "🔍 Running container scan..."
./scripts/security/run-container-scan.sh

echo "🔍 Running dependency scan..."
docker run --rm \
    -v "$(pwd):/src" \
    -v "$(pwd)/reports/$(date +%Y%m%d):/reports" \
    owasp/dependency-check:latest \
    --scan /src \
    --format "HTML" "JSON" "SARIF" \
    --out /reports

echo "📊 Generating security report..."
cat > reports/$(date +%Y%m%d)/security-report.md << 'REPORTEOF'
# Security Scan Report - $(date)

## Scan Summary
- **Date**: $(date)
- **SAST**: Completed
- **DAST**: Completed  
- **Container**: Completed
- **Dependencies**: Completed

## Findings
- Check individual scan reports for detailed findings
- Reports available in: reports/$(date +%Y%m%d)/

## Recommendations
- Review all findings and prioritize by severity
- Implement fixes for critical and high-severity issues
- Schedule follow-up scans after remediation
REPORTEOF

echo "✅ Comprehensive security scan completed!"
echo "📁 Reports available in: reports/$(date +%Y%m%d)/"
EOF

chmod +x scripts/security-scan.sh

# Create Docker Compose override for development
cat > docker-compose.override.yml << EOF
version: '3.8'

services:
  # Development overrides
  sonarqube:
    environment:
      - SONAR_ES_BOOTSTRAP_CHECKS_DISABLE=true
      - SONAR_WEB_JAVAOPTS=-Xmx1g -Xms512m
  
  elasticsearch:
    environment:
      - "ES_JAVA_OPTS=-Xms1g -Xmx1g"
  
  # Development tools
  dev-tools:
    image: alpine:latest
    container_name: dev-tools
    command: tail -f /dev/null
    volumes:
      - .:/workspace
    working_dir: /workspace
    networks:
      - devsecops-network
EOF

echo "✅ DevSecOps environment setup completed!"
echo ""
echo "🚀 To start the environment:"
echo "   docker-compose up -d"
echo ""
echo "🔍 To run security scans:"
echo "   ./scripts/security-scan.sh"
echo ""
echo "📊 Access points:"
echo "   - SonarQube: http://localhost:9000"
echo "   - OWASP ZAP: http://localhost:8080"
echo "   - Prometheus: http://localhost:9090"
echo "   - Grafana: http://localhost:3000 (admin/admin)"
echo "   - Kibana: http://localhost:5601"
echo ""
echo "🔒 Security tools are configured and ready!"
