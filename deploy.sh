source .env

forge script script/DeployGlayzeManager.s.sol --rpc-url $BASE_SEPOLIA_RPC_URL --private-key $PRIVATE_KEY --broadcast --etherscan-api-key $BASESCAN_API_KEY --verify