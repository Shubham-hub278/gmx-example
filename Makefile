-include .env

.PHONY: all test clean deploy-anvil

all: clean remove install build

# Clean the repo
clean  :; forge clean

# Remove modules
remove :; rm -rf .gitmodules && rm -rf .git/modules/* && rm -rf lib && touch .gitmodules && git add . && git commit -m "modules"

install :; forge install OpenZeppelin/openzeppelin-contracts-upgradeable && forge install OpenZeppelin/openzeppelin-contracts && forge install foundry-rs/forge-std --no-commit

# Update Dependencies
update:; forge update

build:; forge build

test :; @forge test --rpc-url ${ARBITRUM_RPC_URL} --match-path test/${contract}.t.sol -vvvv

test-gas-report :; @forge test --rpc-url ${MATIC_RPC_URL} --match-path test/${contract}.t.sol -vv --gas-report

snapshot :; forge snapshot

slither :; slither --config-file slither.config.json  ./src

format :; npx prettier --write src/**/*.sol && prettier --write src/*.sol

test-format :; npx prettier --write test/*.sol

# solhint should be installed globally
lint :; solhint src/**/*.sol && solhint src/*.sol

anvil :; anvil -m 'test test test test test test test test test test test junk'

deploy-arbitrum :; @forge script script/${contract}.s.sol:${contract} --rpc-url ${ARBITRUM_RPC_URL}  --private-key ${PRIVATE_KEY} --broadcast -vv

