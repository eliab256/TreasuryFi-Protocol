# ─── Paths ─────────────────────────────────────────────────────────────────────
UNIT_TEST_PATH        := test/unitTest/**
DEPLOY_IDENTITY       := script/DeployIdentity.s.sol
REGISTER_INVESTOR     := script/RegisterInvetsor.s.sol

# ─── Targets ───────────────────────────────────────────────────────────────────
.PHONY: build test unittest test-bond-automation test-reserves-automation \
        test-single storage coverage coverage-report deploy-identity register-investor

build:
	forge build

test:
	forge test -vv

# ─── Unit tests ──────────────────────────────────────────────────────────────

unittest:
	forge test --match-path '$(UNIT_TEST_PATH)' -vv

test-bond-automation:
	forge test --match-path 'test/unitTest/AutomationUnitTest/BondAutomationTest.t.sol' -vv

test-reserves-automation:
	forge test --match-path 'test/unitTest/AutomationUnitTest/ReservesAutomationTest.t.sol' -vv

# Usage: make test-single NAME=testFunctionName
test-single:
	forge test --match-test $(NAME) -vvvv

# ─── Inspect ─────────────────────────────────────────────────────────────────

# Usage: make storage NAME=Treasury
storage:
	forge inspect $(NAME) storage-layout

# ─── Coverage ────────────────────────────────────────────────────────────────

# Usage: make coverage  (shows coverage only for src/ and script/ files)
coverage:
	@forge coverage --report summary 2>&1 | grep -E '(File|^\| src/|^\| script/|^Total)'

# note: needs lcov installed — sudo apt install lcov
coverage-report:
	forge coverage --report lcov --no-match-coverage "test"
	genhtml lcov.info --output-dir coverage && xdg-open coverage/index.html

# ─── Deploy / scripts ────────────────────────────────────────────────────────

# Usage: make deploy-identity NETWORK=sepolia
deploy-identity:
	forge script $(DEPLOY_IDENTITY) --rpc-url $(NETWORK) --broadcast

# Usage: make register-investor NETWORK=sepolia
register-investor:
	forge script $(REGISTER_INVESTOR) --rpc-url $(NETWORK) --broadcast