#!/bin/bash

# Database Management Script for iac-aws project
# Usage: ./database.sh [command] [environment]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_usage() {
    echo "Database Management Script"
    echo ""
    echo "Usage: $0 [command] [environment]"
    echo ""
    echo "Commands:"
    echo "  deploy       Deploy databases to specified environment"
    echo "  delete       Delete databases from specified environment"
    echo "  status       Check status of database pods"
    echo "  logs         Show logs for database pods"
    echo "  connect-pg   Connect to PostgreSQL (requires psql)"
    echo "  connect-redis Connect to Redis (requires redis-cli)"
    echo "  backup-pg    Create PostgreSQL backup"
    echo "  help         Show this help message"
    echo ""
    echo "Environments:"
    echo "  development  Deploy to development environment"
    echo "  staging      Deploy to staging environment"
    echo "  production   Deploy to production environment"
    echo "  base         Deploy base configuration (no environment prefix)"
    echo ""
    echo "Examples:"
    echo "  $0 deploy development"
    echo "  $0 status production"
    echo "  $0 logs staging"
    echo "  $0 connect-pg development"
}

validate_environment() {
    case $1 in
        development|staging|production|base)
            return 0
            ;;
        *)
            echo -e "${RED}Error: Invalid environment '$1'${NC}"
            echo "Valid environments: development, staging, production, base"
            exit 1
            ;;
    esac
}

get_pod_prefix() {
    case $1 in
        development) echo "dev-" ;;
        staging) echo "staging-" ;;
        production) echo "prod-" ;;
        base) echo "" ;;
    esac
}

deploy_databases() {
    local env=$1
    local prefix=$(get_pod_prefix $env)

    echo -e "${BLUE}Deploying databases to $env environment...${NC}"

    if [ "$env" == "base" ]; then
        echo -e "${YELLOW}Deploying PostgreSQL base...${NC}"
        kubectl apply -k "$PROJECT_ROOT/postgres/base"

        echo -e "${YELLOW}Deploying Redis base...${NC}"
        kubectl apply -k "$PROJECT_ROOT/redis/base"
    else
        echo -e "${YELLOW}Deploying PostgreSQL $env overlay...${NC}"
        kubectl apply -k "$PROJECT_ROOT/postgres/overlays/$env"

        echo -e "${YELLOW}Deploying Redis $env overlay...${NC}"
        kubectl apply -k "$PROJECT_ROOT/redis/overlays/$env"
    fi

    echo -e "${GREEN}Deployment completed!${NC}"
    echo -e "${BLUE}Checking rollout status...${NC}"

    kubectl rollout status statefulset/${prefix}postgres-postgres --timeout=300s
    kubectl rollout status statefulset/${prefix}redis-redis --timeout=300s

    echo -e "${GREEN}All databases are ready!${NC}"
}

delete_databases() {
    local env=$1
    local prefix=$(get_pod_prefix $env)

    echo -e "${YELLOW}Warning: This will delete all database data!${NC}"
    read -p "Are you sure you want to delete databases in $env environment? (y/N): " -n 1 -r
    echo

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${RED}Deleting databases from $env environment...${NC}"

        if [ "$env" == "base" ]; then
            kubectl delete -k "$PROJECT_ROOT/postgres/base" --ignore-not-found=true
            kubectl delete -k "$PROJECT_ROOT/redis/base" --ignore-not-found=true
        else
            kubectl delete -k "$PROJECT_ROOT/postgres/overlays/$env" --ignore-not-found=true
            kubectl delete -k "$PROJECT_ROOT/redis/overlays/$env" --ignore-not-found=true
        fi

        echo -e "${GREEN}Databases deleted!${NC}"
    else
        echo -e "${GREEN}Operation cancelled.${NC}"
    fi
}

check_status() {
    local env=$1
    local prefix=$(get_pod_prefix $env)

    echo -e "${BLUE}Checking database status for $env environment...${NC}"
    echo ""

    echo -e "${YELLOW}PostgreSQL:${NC}"
    kubectl get statefulset,pod,svc,pvc -l app=postgres,environment=$env 2>/dev/null || echo "No PostgreSQL resources found"
    echo ""

    echo -e "${YELLOW}Redis:${NC}"
    kubectl get statefulset,pod,svc,pvc -l app=redis,environment=$env 2>/dev/null || echo "No Redis resources found"
    echo ""

    echo -e "${YELLOW}Pod Health:${NC}"
    kubectl get pods -l "app in (postgres,redis),environment=$env" -o wide 2>/dev/null || echo "No database pods found"
}

show_logs() {
    local env=$1
    local prefix=$(get_pod_prefix $env)

    echo -e "${BLUE}Database logs for $env environment:${NC}"
    echo ""

    echo -e "${YELLOW}PostgreSQL logs:${NC}"
    kubectl logs -l app=postgres,environment=$env --tail=50 --prefix=true 2>/dev/null || echo "No PostgreSQL logs found"

    echo ""
    echo -e "${YELLOW}Redis logs:${NC}"
    kubectl logs -l app=redis,environment=$env --tail=50 --prefix=true 2>/dev/null || echo "No Redis logs found"
}

connect_postgres() {
    local env=$1
    local prefix=$(get_pod_prefix $env)

    echo -e "${BLUE}Connecting to PostgreSQL in $env environment...${NC}"

    local pod_name="${prefix}postgres-postgres-0"
    kubectl exec -it $pod_name -- psql -U postgres -d myapp
}

connect_redis() {
    local env=$1
    local prefix=$(get_pod_prefix $env)

    echo -e "${BLUE}Connecting to Redis in $env environment...${NC}"

    local pod_name="${prefix}redis-redis-0"
    kubectl exec -it $pod_name -- redis-cli -a redis123
}

backup_postgres() {
    local env=$1
    local prefix=$(get_pod_prefix $env)

    echo -e "${BLUE}Creating PostgreSQL backup for $env environment...${NC}"

    local pod_name="${prefix}postgres-postgres-0"
    local backup_file="postgres_backup_$(date +%Y%m%d_%H%M%S).sql"

    kubectl exec $pod_name -- pg_dump -U postgres -d myapp > $backup_file
    echo -e "${GREEN}Backup created: $backup_file${NC}"
}

# Main script logic
case $1 in
    deploy)
        if [ -z "$2" ]; then
            echo -e "${RED}Error: Environment required for deploy command${NC}"
            print_usage
            exit 1
        fi
        validate_environment $2
        deploy_databases $2
        ;;
    delete)
        if [ -z "$2" ]; then
            echo -e "${RED}Error: Environment required for delete command${NC}"
            print_usage
            exit 1
        fi
        validate_environment $2
        delete_databases $2
        ;;
    status)
        if [ -z "$2" ]; then
            echo -e "${RED}Error: Environment required for status command${NC}"
            print_usage
            exit 1
        fi
        validate_environment $2
        check_status $2
        ;;
    logs)
        if [ -z "$2" ]; then
            echo -e "${RED}Error: Environment required for logs command${NC}"
            print_usage
            exit 1
        fi
        validate_environment $2
        show_logs $2
        ;;
    connect-pg)
        if [ -z "$2" ]; then
            echo -e "${RED}Error: Environment required for connect-pg command${NC}"
            print_usage
            exit 1
        fi
        validate_environment $2
        connect_postgres $2
        ;;
    connect-redis)
        if [ -z "$2" ]; then
            echo -e "${RED}Error: Environment required for connect-redis command${NC}"
            print_usage
            exit 1
        fi
        validate_environment $2
        connect_redis $2
        ;;
    backup-pg)
        if [ -z "$2" ]; then
            echo -e "${RED}Error: Environment required for backup-pg command${NC}"
            print_usage
            exit 1
        fi
        validate_environment $2
        backup_postgres $2
        ;;
    help|--help|-h)
        print_usage
        ;;
    *)
        echo -e "${RED}Error: Unknown command '$1'${NC}"
        print_usage
        exit 1
        ;;
esac
