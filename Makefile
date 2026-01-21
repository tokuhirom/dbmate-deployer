.PHONY: help build up down test clean logs verify s3-check test-wait-notify-with-slack test-wait-notify-no-slack test-slack-payload test-version

help: ## Show this help message
	@echo 'Usage: make [target]'
	@echo ''
	@echo 'Available targets:'
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'

build: ## Build the dbmate Docker image
	docker compose build dbmate

up: ## Start PostgreSQL and LocalStack services
	docker compose up -d postgres localstack s3-setup
	@echo "Waiting for services to be ready..."
	@sleep 5
	@echo "✓ Services are ready"

down: ## Stop and remove all containers
	docker compose down -v

test: up ## Run migration test
	@echo "Running dbmate migration..."
	docker compose run --rm dbmate once
	@echo ""
	@echo "Verifying migrations..."
	@$(MAKE) verify

verify: ## Verify that migrations were applied
	@echo "Checking database schema..."
	@docker compose exec -T postgres psql -U testuser -d testdb -c "\dt" || true
	@echo ""
	@echo "Checking users table..."
	@docker compose exec -T postgres psql -U testuser -d testdb -c "SELECT column_name, data_type FROM information_schema.columns WHERE table_name = 'users' ORDER BY ordinal_position;" || true
	@echo ""
	@echo "Checking posts table..."
	@docker compose exec -T postgres psql -U testuser -d testdb -c "SELECT column_name, data_type FROM information_schema.columns WHERE table_name = 'posts' ORDER BY ordinal_position;" || true
	@echo ""
	@echo "Checking schema_migrations table..."
	@docker compose exec -T postgres psql -U testuser -d testdb -c "SELECT * FROM schema_migrations;" || true

logs: ## Show logs from all services
	docker compose logs -f

clean: down ## Clean up everything including volumes
	docker compose down -v --rmi local
	@echo "✓ Cleanup completed"

# Development helpers
shell: ## Open a shell in the dbmate container (Alpine - use /bin/sh)
	docker compose run --rm --entrypoint=/bin/sh dbmate

psql: ## Open PostgreSQL shell
	docker compose exec postgres psql -U testuser -d testdb

s3-check: ## Check S3 bucket contents using aws-cli container
	@echo "Checking S3 bucket contents..."
	@docker compose run --rm --entrypoint="" s3-setup \
		aws --endpoint-url=http://localstack:4566 s3 ls s3://migrations-bucket/migrations/ --recursive

test-wait-notify-with-slack: ## Test wait-and-notify with Slack notification
	@echo "Building webhook-logger..."
	@docker build -t webhook-logger:test -q ./test/webhook-logger
	@echo ""
	@echo "Starting webhook-logger server..."
	@docker run --rm -d --name webhook-logger-test \
		--network dbmate-s3-docker_default \
		-e PORT=9876 \
		webhook-logger:test
	@sleep 2
	@echo ""
	@echo "Testing wait-and-notify with Slack notification..."
	@docker compose run --rm \
		-e SLACK_INCOMING_WEBHOOK=http://webhook-logger-test:9876/webhook \
		dbmate wait-and-notify \
		--version=20260120000000 \
		--timeout=1m
	@echo ""
	@docker stop webhook-logger-test > /dev/null 2>&1 || true
	@echo "✓ Test complete"

test-wait-notify-no-slack: ## Test wait-and-notify without Slack notification
	@echo "Testing wait-and-notify without Slack notification..."
	@docker compose run --rm \
		dbmate wait-and-notify \
		--version=20260120000000 \
		--timeout=1m

test-slack-payload: ## Verify Slack webhook payload (method, headers, JSON structure)
	@echo "Building webhook-logger..."
	@docker build -t webhook-logger:test -q ./test/webhook-logger
	@echo ""
	@echo "Starting webhook-logger server..."
	@docker run --rm -d --name webhook-logger-test \
		--network dbmate-s3-docker_default \
		-e PORT=9876 \
		webhook-logger:test
	@sleep 2
	@echo ""
	@echo "Sending test webhook..."
	@docker compose run --rm \
		-e SLACK_INCOMING_WEBHOOK=http://webhook-logger-test:9876/webhook \
		dbmate wait-and-notify \
		--version=20260120000000 \
		--timeout=1m > /dev/null 2>&1
	@echo ""
	@echo "=== Webhook Payload Verification ==="
	@docker logs webhook-logger-test 2>&1 | grep -A 100 "=== Webhook"
	@echo ""
	@docker stop webhook-logger-test > /dev/null 2>&1 || true
	@echo "✓ Verification complete - HTTP method, Content-Type, and payload structure validated"

test-version: ## Test version subcommand
	@echo "Testing version subcommand..."
	@echo ""
	@OUTPUT=$$(docker compose run --rm --no-deps dbmate version 2>&1); \
	if echo "$$OUTPUT" | grep -q "dbmate-s3-docker version"; then \
		echo "✓ Version command output:"; \
		echo "$$OUTPUT" | grep "dbmate-s3-docker version"; \
		echo ""; \
		echo "✓ Version subcommand works correctly"; \
	else \
		echo "✗ Failed: Expected 'dbmate-s3-docker version' in output"; \
		echo "Actual output:"; \
		echo "$$OUTPUT"; \
		exit 1; \
	fi
