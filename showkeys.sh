#!/bin/bash


CYAN='\033[1;36m'
GREEN='\033[1;32m'
NC='\033[0m'

if [ -f "/opt/aya/registration.json" ]; then
OPERATOR_ADDRESS=$(cat /opt/aya/registration.json | jq -r '.operator_address')
OPERATOR_HEX=$(ayad keys parse $OPERATOR_ADDRESS --output json | jq -r '.bytes')
VALIDATOR_ADDRESS=$(cat /opt/aya/registration.json | jq -r '.validator_address')
VALIDATOR_HEX=$(ayad keys parse $VALIDATOR_ADDRESS --output json | jq -r '.bytes')
MONIKER=$(cat /opt/aya/registration.json | jq -r '.moniker')
echo -e "${CYAN}$MONIKER : THIS IS A VALIDATOR NODE{NC}"
echo ""
echo -e "${CYAN}OPERATOR${NC}"
echo -e "  ${GREEN}$OPERATOR_HEX${NC}"
echo -e "  ${GREEN}$(ayad keys parse $OPERATOR_HEX --output json | jq -r '.formats[0]')${NC}"
echo -e "  ${GREEN}$(ayad keys parse $OPERATOR_HEX --output json | jq -r '.formats[2]')${NC}"
echo -e "${CYAN}CONSENSUS${NC}"
echo -e "  ${GREEN}$VALIDATOR_HEX${NC}"
echo -e "  ${GREEN}$(ayad keys parse $VALIDATOR_HEX --output json | jq -r '.formats[4]')${NC}"
echo -e "  ${GREEN}$(ayad keys parse $VALIDATOR_HEX --output json | jq -r '.formats[5]')${NC}"
echo -e "${CYAN}NODE ID${NC}"
echo -e "  ${GREEN}$(ayad tendermint show-node-id --home /opt/aya)${NC}"
else if [ -f "/opt/aya/sentry.json" ]; then
VALIDATOR_ADDRESS=$(cat /opt/aya/sentry.json | jq -r '.validator_address')
VALIDATOR_HEX=$(ayad keys parse $VALIDATOR_ADDRESS --output json | jq -r '.bytes')
MONIKER=$(cat /opt/aya/sentry.json | jq -r '.moniker')
echo -e "${CYAN}$MONIKER: THIS IS A RELAY NODE${NC}"
echo ""
echo -e "${CYAN}CONSENSUS${NC}"
echo -e "  ${GREEN}$VALIDATOR_HEX${NC}"
echo -e "  ${GREEN}$(ayad keys parse $VALIDATOR_HEX --output json | jq -r '.formats[4]')${NC}"
echo -e "  ${GREEN}$(ayad keys parse $VALIDATOR_HEX --output json | jq -r '.formats[5]')${NC}"
echo -e "${CYAN}NODE ID${NC}"
echo -e "  ${GREEN}$(ayad tendermint show-node-id --home /opt/aya)${NC}"
fi
fi
