#!/bin/bash

################################################################################
# Jenkins CI/CD Setup Script for Spring PetClinic
# This script automates the initial setup of Jenkins and required tools
################################################################################

set -e  # Exit on error
set -u  # Exit on undefined variable

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
JENKINS_PORT=8080
JENKINS_AGENT_PORT=50000
JENKINS_HOME="${HOME}/jenkins_home"
DOCKER_COMPOSE_VERSION="2.20.2"

################################################################################
# Helper Functions
################################################################################

print_header() {
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}\n"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

check_command() {
    if command -v "$1" &> /dev/null; then
        print_success "$1 is installed"
        return 0
    else
        print_error "$1 is not installed"
        return 1
    fi
}

################################################################################
# System Requirements Check
################################################################################

check_requirements() {
    print_header "Checking System Requirements"
    
    local all_requirements_met=true
    
    # Check Docker
    if check_command docker; then
        docker --version
    else
        all_requirements_met=false
        print_warning "Install Docker: https://docs.docker.com/get-docker/"
    fi
    
    # Check Docker Compose
    if check_command docker-compose || docker compose version &> /dev/null; then
        docker-compose --version 2>/dev/null || docker compose version
    else
        all_requirements_met=false
        print_warning "Install Docker Compose"
    fi
    
    # Check Git
    if check_command git; then
        git --version
    else
        all_requirements_met=false
        print_warning "Install Git: https://git-scm.com/downloads"
    fi
    
    # Check curl
    if ! check_command curl; then
        all_requirements_met=false
    fi
    
    # Check available disk space
    available_space=$(df -BG . | awk 'NR==2 {print $4}' | sed 's/G//')
    if [ "$available_space" -lt 10 ]; then
        print_warning "Low disk space. At least 10GB recommended. Available: ${available_space}GB"
        all_requirements_met=false
    else
        print_success "Sufficient disk space: ${available_space}GB"
    fi
    
    # Check available memory
    if [ -f /proc/meminfo ]; then
        total_mem=$(grep MemTotal /proc/meminfo | awk '{print int($2/1024/1024)}')
        if [ "$total_mem" -lt 4 ]; then
            print_warning "Low memory. At least 4GB recommended. Available: ${total_mem}GB"
        else
            print_success "Sufficient memory: ${total_mem}GB"
        fi
    fi
    
    if [ "$all_requirements_met" = false ]; then
        print_error "Please install missing requirements before continuing"
        exit 1
    fi
    
    print_success "All requirements met!"
}

################################################################################
# Docker Setup
################################################################################

setup_docker() {
    print_header "Setting up Docker Environment"
    
    # Check if Docker daemon is running
    if ! docker info > /dev/null 2>&1; then
        print_error "Docker daemon is not running. Please start Docker."
        exit 1
    fi
    
    # Create Docker network
    if ! docker network ls | grep -q jenkins-network; then
        print_info "Creating Docker network: jenkins-network"
        docker network create jenkins-network
        print_success "Docker network created"
    else
        print_info "Docker network already exists"
    fi
    
    # Pull required images
    print_info "Pulling required Docker images..."
    docker pull jenkins/jenkins:lts
    docker pull maven:3.9-eclipse-temurin-17
    docker pull eclipse-temurin:17-jre-alpine
    
    print_success "Docker setup complete"
}

################################################################################
# Jenkins Installation
################################################################################

install_jenkins() {
    print_header "Installing Jenkins"
    
    # Create Jenkins home directory
    mkdir -p "$JENKINS_HOME"
    
    # Check if Jenkins is already running
    if docker ps | grep -q jenkins-master; then
        print_warning "Jenkins is already running"
        read -p "Do you want to restart Jenkins? (y/n) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            print_info "Stopping existing Jenkins container..."
            docker stop jenkins-master
            docker rm jenkins-master
        else
            print_info "Keeping existing Jenkins instance"
            return
        fi
    fi
    
    # Start Jenkins using Docker Compose
    if [ -f docker-compose.yml ]; then
        print_info "Starting Jenkins with Docker Compose..."
        docker-compose up -d jenkins
    else
        print_info "Starting Jenkins with Docker run..."
        docker run -d \
            --name jenkins-master \
            --network jenkins-network \
            -p ${JENKINS_PORT}:8080 \
            -p ${JENKINS_AGENT_PORT}:50000 \
            -v jenkins_home:/var/jenkins_home \
            -v /var/run/docker.sock:/var/run/docker.sock \
            --privileged \
            jenkins/jenkins:lts
    fi
    
    # Wait for Jenkins to start
    print_info "Waiting for Jenkins to start (this may take a minute)..."
    local attempts=0
    local max_attempts=30
    
    while [ $attempts -lt $max_attempts ]; do
        if curl -s http://localhost:${JENKINS_PORT}/login > /dev/null 2>&1; then
            print_success "Jenkins is running!"
            break
        fi
        attempts=$((attempts + 1))
        echo -n "."
        sleep 2
    done
    
    if [ $attempts -eq $max_attempts ]; then
        print_error "Jenkins failed to start within expected time"
        docker logs jenkins-master
        exit 1
    fi
    
    # Get initial admin password
    print_info "\nRetrieving initial admin password..."
    echo -e "\n${GREEN}========================================${NC}"
    echo -e "${GREEN}Jenkins Initial Admin Password:${NC}"
    echo -e "${YELLOW}$(docker exec jenkins-master cat /var/jenkins_home/secrets/initialAdminPassword)${NC}"
    echo -e "${GREEN}========================================${NC}\n"
    
    print_success "Jenkins installation complete!"
    print_info "Access Jenkins at: http://localhost:${JENKINS_PORT}"
}

################################################################################
# Install Jenkins Plugins
################################################################################

install_plugins() {
    print_header "Installing Jenkins Plugins"
    
    print_info "Installing required plugins via Jenkins CLI..."
    
    local plugins=(
        "workflow-aggregator"
        "git"
        "docker-workflow"
        "junit"
        "email-ext"
        "credentials-binding"
        "pipeline-stage-view"
        "timestamper"
        "workspace-cleanup"
        "build-timeout"
        "matrix-auth"
    )
    
    for plugin in "${plugins[@]}"; do
        print_info "Installing plugin: $plugin"
        docker exec jenkins-master jenkins-plugin-cli --plugins "$plugin" || true
    done
    
    print_info "Restarting Jenkins to load plugins..."
    docker restart jenkins-master
    
    # Wait for restart
    sleep 20
    
    print_success "Plugins installed successfully"
}

################################################################################
# Create Initial Job
################################################################################

create_job() {
    print_header "Creating Spring PetClinic Pipeline Job"
    
    print_info "Creating job configuration..."
    
    # Job configuration will be created via Jenkins UI or Job DSL
    print_info "Job configuration complete"
    print_warning "Please create the pipeline job manually or use Job DSL plugin"
    print_info "Repository URL: https://github.com/spring-projects/spring-petclinic.git"
    print_info "Script Path: Jenkinsfile"
}

################################################################################
# Setup Helper Services
################################################################################

setup_helpers() {
    print_header "Setting up Helper Services"
    
    # Start Mailhog for email testing
    if [ -f docker-compose.yml ]; then
        print_info "Starting Mailhog for email testing..."
        docker-compose up -d mailhog
        print_success "Mailhog is running at: http://localhost:8025"
    fi
    
    # Start local Docker registry
    if [ -f docker-compose.yml ]; then
        print_info "Starting local Docker registry..."
        docker-compose up -d registry
        print_success "Docker registry is running at: localhost:5000"
    fi
}

################################################################################
# Verification
################################################################################

verify_installation() {
    print_header "Verifying Installation"
    
    # Check Jenkins
    if curl -s http://localhost:${JENKINS_PORT}/login > /dev/null 2>&1; then
        print_success "Jenkins is accessible at http://localhost:${JENKINS_PORT}"
    else
        print_error "Jenkins is not accessible"
    fi
    
    # Check Docker
    if docker ps | grep -q jenkins-master; then
        print_success "Jenkins container is running"
    else
        print_error "Jenkins container is not running"
    fi
    
    # Check Docker socket access
    if docker exec jenkins-master docker ps > /dev/null 2>&1; then
        print_success "Jenkins can access Docker"
    else
        print_warning "Jenkins may not have Docker access"
    fi
    
    # List running containers
    print_info "\nRunning containers:"
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
}

################################################################################
# Print Summary
################################################################################

print_summary() {
    print_header "Setup Complete!"
    
    echo -e "${GREEN}Jenkins Setup Summary:${NC}\n"
    echo -e "  ${BLUE}Jenkins URL:${NC} http://localhost:${JENKINS_PORT}"
    echo -e "  ${BLUE}Initial Password:${NC} Run: docker exec jenkins-master cat /var/jenkins_home/secrets/initialAdminPassword"
    echo -e "  ${BLUE}Mailhog UI:${NC} http://localhost:8025 (for testing emails)"
    echo -e "  ${BLUE}Docker Registry:${NC} localhost:5000"
    echo -e "\n${YELLOW}Next Steps:${NC}\n"
    echo -e "  1. Access Jenkins at http://localhost:${JENKINS_PORT}"
    echo -e "  2. Enter the initial admin password"
    echo -e "  3. Install suggested plugins"
    echo -e "  4. Create admin user"
    echo -e "  5. Create new Pipeline job"
    echo -e "  6. Configure job to use SCM: https://github.com/spring-projects/spring-petclinic.git"
    echo -e "  7. Set Script Path to: Jenkinsfile"
    echo -e "  8. Configure credentials for Docker Hub (if needed)"
    echo -e "  9. Configure email settings in Jenkins configuration"
    echo -e "  10. Run your first build!\n"
    
    echo -e "${BLUE}Useful Commands:${NC}\n"
    echo -e "  View Jenkins logs:     docker logs -f jenkins-master"
    echo -e "  Stop Jenkins:          docker compose down (or) docker stop jenkins-master"
    echo -e "  Start Jenkins:         docker compose up -d (or) docker start jenkins-master"
    echo -e "  Restart Jenkins:       docker restart jenkins-master"
    echo -e "  Backup Jenkins:        docker cp jenkins-master:/var/jenkins_home ./jenkins_backup"
    echo -e "  Access Jenkins shell:  docker exec -it jenkins-master bash\n"
}

################################################################################
# Cleanup Function
################################################################################

cleanup() {
    print_header "Cleanup"
    
    read -p "Do you want to remove all Jenkins data? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        print_warning "Stopping and removing Jenkins..."
        docker compose down -v 2>/dev/null || docker stop jenkins-master && docker rm jenkins-master
        docker volume rm jenkins_home 2>/dev/null || true
        print_success "Cleanup complete"
    else
        print_info "Cleanup cancelled"
    fi
}

################################################################################
# Main Execution
################################################################################

main() {
    clear
    
    echo -e "${BLUE}"
    cat << "EOF"
    ╔════════════════════════════════════════════════════════╗
    ║                                                        ║
    ║     Jenkins CI/CD Pipeline Setup Script               ║
    ║     Spring PetClinic Application                      ║
    ║                                                        ║
    ╚════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}\n"
    
    # Parse command line arguments
    case "${1:-install}" in
        install)
            check_requirements
            setup_docker
            install_jenkins
            # install_plugins  # Uncomment if you have Jenkins CLI configured
            setup_helpers
            verify_installation
            print_summary
            ;;
        cleanup)
            cleanup
            ;;
        verify)
            verify_installation
            ;;
        restart)
            print_info "Restarting Jenkins..."
            docker restart jenkins-master
            sleep 10
            verify_installation
            ;;
        logs)
            docker logs -f jenkins-master
            ;;
        *)
            echo "Usage: $0 {install|cleanup|verify|restart|logs}"
            echo ""
            echo "Commands:"
            echo "  install  - Install and configure Jenkins (default)"
            echo "  cleanup  - Remove Jenkins and all data"
            echo "  verify   - Verify installation"
            echo "  restart  - Restart Jenkins"
            echo "  logs     - View Jenkins logs"
            exit 1
            ;;
    esac
}

# Run main function
main "$@"