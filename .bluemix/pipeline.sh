#!/bin/bash
set -ex
trap 'detect_exit' 0 1 2 3 6

export IBP_NAME="ibm-blockchain-5-prod"
export IBP_PLAN="ibm-blockchain-plan-v1-ga1-starter-prod"
export VCAP_KEY_NAME="Credentials-1"
export APP_URL="unknown_yet"  # we correct this later

detect_exit() {
    if [ "$COMPLETED_STEP" != "6" ]; then
      printf "\n\n --- Uh oh something failed... ---\n"
      export COMPLETED_STEP="tc_error"
      if [ "$API_URL" != "" ]; then
        update_status
      fi
    else
      echo "Script completed successfully. =)"
    fi
}

update_status() {
    echo "Updating Deployment Status - ${NETWORKID}"
    echo '{"app": "'"$CF_APP"'", "url": "'"$APP_URL"'", "completed_step": "'"$COMPLETED_STEP"'"}' \
    echo curl -X PUT -s -S\
      "$API_HOST/api/v1/networks/$NETWORKID/sample/letters_of_credit" \
      -H 'Cache-Control: no-cache' \
      -H 'Content-Type: application/json' \
      -u $USERID:$PASSWORD \
      -d '{"app": "'"$CF_APP"'", "url": "'"$APP_URL"'", "completed_step": "'"$COMPLETED_STEP"'"}'
    curl -X PUT -s -S\
      "$API_HOST/api/v1/networks/$NETWORKID/sample/letters_of_credit" \
      -H 'Cache-Control: no-cache' \
      -H 'Content-Type: application/json' \
      -u $USERID:$PASSWORD \
      -d '{"app": "'"$CF_APP"'", "url": "'"$APP_URL"'", "completed_step": "'"$COMPLETED_STEP"'"}' \
      | jq '.' || true
}

get_connection_profile() {
    echo curl -X GET --header 'Content-Type: application/json' --header 'Accept: application/json' --basic --user ${USERID}:${PASSWORD} ${API_HOST}/api/v1/networks/${NETWORKID}/connection_profile
    curl -X GET --header 'Content-Type: application/json' --header 'Accept: application/json' --basic --user ${USERID}:${PASSWORD} ${API_HOST}/api/v1/networks/${NETWORKID}/connection_profile > ./config/connection-profile.json
}

install_playground() {
    # -----------------------------------------------------------
    # Install Composer Playground
    # -----------------------------------------------------------
    date
    printf "\n ---- Install composer-playground ----- \n"
    cf push composer-playground-${CF_APP} --docker-image sstone1/composer-playground:0.19.4 -i 1 -m 256M --no-start --no-manifest
    cf set-env composer-playground-${CF_APP} NODE_CONFIG "${NODE_CONFIG}"
    cf start composer-playground-${CF_APP}

    date
    printf "\n ---- Installed composer-playground ----- \n"
}

push_restserver() {
    date
    printf "\n----- Pushing REST server ----- \n"
    cf push composer-rest-server-${CF_APP} --docker-image sstone1/composer-rest-server:0.19.4 -c "composer-rest-server -c admin@letters-of-credit-network -n never -w true" -i 1 -m 256M --no-start --no-manifest
    cf set-env composer-rest-server-${CF_APP} NODE_CONFIG "${NODE_CONFIG}"

    date
    printf "\n----- Pushed REST server ----- \n"
}

start_restserver() {
    printf "\n----- Start REST server ----- \n"
    date
    cf start composer-rest-server-${CF_APP}
    date
    printf "\n----- Started REST server ----- \n"
}

push_app() {
    # Bind app to the blockchain service
    # Push app (don't start yet, wait for binding)
    date
    printf "\n --- Getting the Letters of credit application '${CF_APP}' ---\n"
    npm install letters-of-credit@0.0.10
    cd node_modules/letters-of-credit
    export REST_SERVER_URL=$(cf app composer-rest-server-${CF_APP} | grep routes: | awk '{print $2}')
    export PLAYGROUND_URL=$(cf app composer-playground-${CF_APP} | grep routes: | awk '{print $2}')
    touch .env
    echo "REACT_APP_REST_SERVER_CONFIG='{\"webSocketURL\": \"wss://${REST_SERVER_URL}\", \"httpURL\": \"https://${REST_SERVER_URL}/api\", \"explorer\": \"https://${REST_SERVER_URL}/explorer\"}'"  > .env
    echo "REACT_APP_PLAYGROUND_CONFIG='{\"name\": \"IBM Blockchain Platform: Develop\", \"docURL\": \"https://console.bluemix.net/docs/services/blockchain/develop.html#develop-the-network\", \"deployedURL\": \"https://${PLAYGROUND_URL}\"}'" >> .env
    npm run build
    cd build
    touch Staticfile
    echo 'pushstate: enabled' > Staticfile

    date
    printf "\n --- Pushing the Letters of credit application '${CF_APP}' ---\n"
    cf push ${CF_APP} -m 64M --no-start --no-manifest
    date
    printf "\n --- Pushed the Letters of credit application '${CF_APP}' ---\n"
    cd ../../../..
}

start_app() {
    date
    printf "\n --- Binding the IBM Blockchain Platform service to Letters of credit app ---\n"
    cf bind-service ${CF_APP} "${SERVICE_INSTANCE_NAME}" -c "{\"permissions\":\"read-only\"}"

    # Start her up
    date
    printf "\n --- Starting letters of credit app '${CF_APP}' ---\n"
    cf start ${CF_APP}

    date
    printf "\n --- Started the letters of credit application '${CF_APP}' ---\n"
}

date
printf "\n ---- Install node and nvm ----- \n"
npm config delete prefix
     curl -o- https://raw.githubusercontent.com/creationix/nvm/v0.33.8/install.sh | bash
     export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    nvm install --lts
nvm use node

node -v

date
printf "\n ---- Installed node and nvm ----- \n"

# -----------------------------------------------------------
# Detect if there is already a service we should use - [ Optional ]
# -----------------------------------------------------------
printf "\n --- Detecting service options ---\n"
if [ "$SERVICE_INSTANCE_NAME" != "" ]; then
    echo "A service instance name was provided, lets use that"
else
    echo "A service instance name was NOT provided, lets use the default one"
    export SERVICE_INSTANCE_NAME="blockchain-${CF_APP}"
fi
    printf "Using service instance name '${SERVICE_INSTANCE_NAME}'\n"

# -----------------------------------------------------------
# 1. Test if everything we need is set
# -----------------------------------------------------------
printf "\n --- Testing if the script has what it needs ---\n"
export SCRIPT_ERROR="nope"
if [ "$IBP_NAME" == "" ]; then
    echo "Error - bad script setup - IBP_NAME was not provided (IBM Blockchain service name)"
    export SCRIPT_ERROR="yep"
fi

if [ "$IBP_PLAN" == "" ]; then
echo "Error - bad script setup - IBP_PLAN was not provided (IBM Blockchain service's plan name)"
export SCRIPT_ERROR="yep"
fi

if [ "$VCAP_KEY_NAME" == "" ]; then
echo "Error - bad script setup - VCAP_KEY_NAME was not provided (Bluemix service credential key name)"
export SCRIPT_ERROR="yep"
fi

if [ "$SERVICE_INSTANCE_NAME" == "" ]; then
echo "Error - bad script setup - SERVICE_INSTANCE_NAME was not provided (IBM Blockchain service instance name)"
export SCRIPT_ERROR="yep"
fi

if [ "$CF_APP" == "" ]; then
echo "Error - bad script setup - CF_APP was not provided (Letters of credit application name)"
export SCRIPT_ERROR="yep"
fi

if [ "$SCRIPT_ERROR" == "yep" ]; then
exit 1
else
echo "All good"
fi

# -----------------------------------------------------------
# 2. Create a service instance (this is okay to run if the service name already exists as long as its the same typeof service)
# -----------------------------------------------------------
date
printf "\n --- Creating an instance of the IBM Blockchain Platform service ---\n"
# Only create the service if it doesn't already exist.
if ! cf service "${SERVICE_INSTANCE_NAME}" > /dev/null 2>&1; then
cf create-service ${IBP_NAME} ${IBP_PLAN} "${SERVICE_INSTANCE_NAME}"
fi

cf create-service-key "${SERVICE_INSTANCE_NAME}" ${VCAP_KEY_NAME} -c '{"msp_id":"PeerOrg1"}'

date
printf "\n --- Creating an instance of the Cloud object store ---\n"
cf create-service cloudantNoSQLDB Lite cloudant-${CF_APP}
cf create-service-key cloudant-${CF_APP} ${VCAP_KEY_NAME}
date
printf "\n --- Created an instance of the Cloud object store ---\n"

# -----------------------------------------------------------
# 3. Get service credentials into our file system (remove the first two lines from cf service-key output)
# -----------------------------------------------------------
date
printf "\n --- Getting service credentials ---\n"
cf service-key "${SERVICE_INSTANCE_NAME}" ${VCAP_KEY_NAME} > ./config/temp.txt
tail -n +2 ./config/temp.txt > ./config/loc_tc.json

curl -o jq -L https://github.com/stedolan/jq/releases/download/jq-1.5/jq-linux64
chmod +x jq
export PATH=$PATH:$PWD

export NETWORKID=$(jq --raw-output '.org1."network_id"' ./config/loc_tc.json)
printf "\n networkid ${NETWORKID} \n"

export USERID=$(jq --raw-output '.org1.key' ./config/loc_tc.json)
printf "\n userid ${USERID} \n"

export PASSWORD=$(jq --raw-output '.org1.secret' ./config/loc_tc.json)
printf "\n password ${PASSWORD} \n"

export API_HOST=$(jq --raw-output '.org1.url' ./config/loc_tc.json)
printf "\n apiurl ${API_HOST} \n"

#cf service-key cloudant-${CLOUDANT_SERVICE_INSTANCE} ${VCAP_KEY_NAME} > ./config/cloudant-creds-temp.txt
cf service-key cloudant-${CF_APP} ${VCAP_KEY_NAME} > ./config/cloudant-creds-temp.txt
tail -n +2 ./config/cloudant-creds-temp.txt > ./config/cloudant-creds.txt

cat ./config/cloudant-creds.txt

export CLOUDANT_URL=$(jq --raw-output '.url' ./config/cloudant-creds.txt)

echo curl -X PUT ${CLOUDANT_URL}/${CF_APP}
   curl -X PUT ${CLOUDANT_URL}/${CF_APP}

export CLOUDANT_CREDS=$(jq ". + {database: \"${CF_APP}\"}" ./config/cloudant-creds.txt)

printf "\n ${CLOUDANT_CREDS} \n"

get_connection_profile
while ! jq -e ".channels.defaultchannel" ./config/connection-profile.json
do
sleep 10
get_connection_profile
done


#echo curl -X GET --header 'Content-Type: application/json' --header 'Accept: application/json' --basic --user ${USERID}:${PASSWORD} ${API_HOST}/api/v1/networks/${NETWORKID}/connection_profile
#     curl -X GET --header 'Content-Type: application/json' --header 'Accept: application/json' --basic --user ${USERID}:${PASSWORD} ${API_HOST}/api/v1/networks/${NETWORKID}/connection_profile > ./config/connection-profile.json

printf "\n --- connection-profile.json --- \n"
cat ./config/connection-profile.json

export SECRET=$(jq --raw-output 'limit(1;.certificateAuthorities[].registrar[0].enrollSecret)' ./config/connection-profile.json)
printf "\n secret ${SECRET} \n"

export MSPID=$(jq --raw-output 'limit(1; .organizations[].mspid)' ./config/connection-profile.json)
printf "\n mspid ${MSPID} \n"

export PEER=$(jq --raw-output 'limit(1; .organizations[].peers[0])' ./config/connection-profile.json)
printf "\n peer ${PEER} \n"

export CHANNEL="defaultchannel"

export COMPLETED_STEP="1"
update_status

date
printf "\n --- Got service credentials ---\n"

# -----------------------------------------------------------
# 4. Install composer-cli
# -----------------------------------------------------------
  date
  printf "\n ---- Install composer-cli and composer-wallet-cloudant ----- \n "

  npm install -g composer-cli@0.19.4 @ampretia/composer-wallet-cloudant

  composer -v

  date
  printf "\n ---- Installed composer-cli and composer-wallet-cloudant ----- \n "

# -----------------------------------------------------------
# Create Composer configuration for Cloudant wallet
# -----------------------------------------------------------
date
printf "\n --- create composer configuration --- \n"

read -d '' NODE_CONFIG << EOF || true
{"composer":{"wallet":{"type":"@ampretia/composer-wallet-cloudant","desc":"Uses cloud wallet","options":${CLOUDANT_CREDS}}}}
EOF
export NODE_CONFIG

date
printf "\n --- created composer configuration --- \n"

# -----------------------------------------------------------
# start pushing playground, rest server, and app to ibm cloud
# -----------------------------------------------------------

install_playground &

export PLAYGROUND_PID=$!

push_restserver &

export REST_PID=$!

push_app &

export APP_PID=$!

# -----------------------------------------------------------
# 5. Add and sync admin cert
# -----------------------------------------------------------
date
printf "\n ----- create ca card ----- \n"
composer card create -f ca.card -p ./config/connection-profile.json -u admin -s ${SECRET}
composer card import -f ca.card -c ca
# request identity
composer identity request --card ca --path ./credentials
composer card delete -c ca
export PUBLIC_CERT=$(cat ./credentials/admin-pub.pem | tr '\n' '~' | sed 's/~/\\r\\n/g')

# add admin cert
date
printf "\n ----- add certificate ----- \n"
cat << EOF > request.json
{
"msp_id": "${MSPID}",
"peers": ["${PEER}"],
"adminCertName": "my cert",
"adminCertificate": "${PUBLIC_CERT}"
}
EOF

cat request.json
echo curl -X POST --header 'Content-Type: application/json' --header 'Accept: application/json' --basic --user ${USERID}:${PASSWORD} --data-binary @request.json ${API_HOST}/api/v1/networks/${NETWORKID}/certificates
  curl -X POST --header 'Content-Type: application/json' --header 'Accept: application/json' --basic --user ${USERID}:${PASSWORD} --data-binary @request.json ${API_HOST}/api/v1/networks/${NETWORKID}/certificates

# stop peer
date
printf "\n ----- stop peer ----- \n"
echo curl -X POST --header 'Content-Type: application/json' --header 'Accept: application/json' --basic --user ${USERID}:${PASSWORD} --data-binary '{}' ${API_HOST}/api/v1/networks/${NETWORKID}/nodes/${PEER}/stop
     curl -X POST --header 'Content-Type: application/json' --header 'Accept: application/json' --basic --user ${USERID}:${PASSWORD} --data-binary '{}' ${API_HOST}/api/v1/networks/${NETWORKID}/nodes/${PEER}/stop

# start peer
date
printf "\n ----- start peer ----- \n"
echo curl -X POST --header 'Content-Type: application/json' --header 'Accept: application/json' --basic --user ${USERID}:${PASSWORD} --data-binary '{}' ${API_HOST}/api/v1/networks/${NETWORKID}/nodes/${PEER}/start
     curl -X POST --header 'Content-Type: application/json' --header 'Accept: application/json' --basic --user ${USERID}:${PASSWORD} --data-binary '{}' ${API_HOST}/api/v1/networks/${NETWORKID}/nodes/${PEER}/start


#wait for peer to start
date
printf "\n ----- wait for peer to start --- \n"

export PEER_STATUS="not running"
i=0

while [[ "$PEER_STATUS" != "running" && "$i" -lt "12" ]]
do
    sleep 10s
    echo curl -X GET --header 'Content-Type: application/json' --header 'Accept: application/json' --basic --user ${USERID}:${PASSWORD} ${API_HOST}/api/v1/networks/${NETWORKID}/nodes/status
    STATUS=$(curl -X GET --header 'Content-Type: application/json' --header 'Accept: application/json' --basic --user ${USERID}:${PASSWORD} ${API_HOST}/api/v1/networks/${NETWORKID}/nodes/status)
    PEER_STATUS=$(echo ${STATUS} | jq --raw-output ".[\"${PEER}\"].status")
    i=$[$i+1]
done

# sync certificates
date
printf "\n ----- sync certificate ----- \n"
echo curl -X POST --header 'Content-Type: application/json' --header 'Accept: application/json' --basic --user ${USERID}:${PASSWORD} --data-binary '{}' ${API_HOST}/api/v1/networks/${NETWORKID}/channels/${CHANNEL}/sync
  curl -X POST --header 'Content-Type: application/json' --header 'Accept: application/json' --basic --user ${USERID}:${PASSWORD} --data-binary '{}' ${API_HOST}/api/v1/networks/${NETWORKID}/channels/${CHANNEL}/sync

date
printf "\n ----- created ca card ----- \n"

## -----------------------------------------------------------
## 6. Create new card
## -----------------------------------------------------------
date
printf "\n ---- Create admin card ----- \n "
composer card create -f adminCard.card -p ./config/connection-profile.json -u admin -c ./credentials/admin-pub.pem -k ./credentials/admin-priv.pem --role PeerAdmin --role ChannelAdmin

composer card import -f adminCard.card -c admin@blockchain-network
date
printf "\n ---- Created admin card ----- \n "

## -----------------------------------------------------------
## 7. Deploy the network
## -----------------------------------------------------------
date
printf "\n --- get network --- \n"
npm install letters-of-credit-network@0.2.5
date
printf "\n --- got network --- \n"

date
printf "\n --- create archive --- \n"
BUSINESS_NETWORK_VERSION=$(jq --raw-output '.version' ./node_modules/letters-of-credit-network/package.json)
composer archive create -a ./letters-of-credit-network.bna -t dir -n node_modules/letters-of-credit-network
date
printf "\n --- created archive --- \n"

date
printf "\n --- install network --- \n"
while ! composer network install -c admin@blockchain-network -a ./letters-of-credit-network.bna; do
echo sleeping to retry runtime install
sleep 30s
done
date
printf "\n --- installed network --- \n"

export COMPLETED_STEP="2"
update_status

date
printf "\n --- start network --- \n"

while ! composer network start -c admin@blockchain-network -n letters-of-credit-network -V ${BUSINESS_NETWORK_VERSION} -A admin -C ./credentials/admin-pub.pem -f delete_me.card; do
echo sleeping to retry network start
sleep 30s
done

export COMPLETED_STEP="3"
update_status

date
printf "\n --- started network --- \n"

# -----------------------------------------------------------
# Import business network card into Cloudant wallet
# -----------------------------------------------------------
date
printf "\n --- import business network card --- \n"

composer card create -n letters-of-credit-network -p ./config/connection-profile.json -u admin -c ./credentials/admin-pub.pem -k ./credentials/admin-priv.pem

composer card import -f ./admin@letters-of-credit-network.card

while ! composer network ping -c admin@letters-of-credit-network; do sleep 5; done


date
printf "\n --- setup demo --- \n"
composer transaction submit -c admin@letters-of-credit-network -d '{"$class": "org.example.loc.CreateDemoParticipants"}'

date
printf "\n --- imported business network card --- \n"

# -----------------------------------------------------------
# Wait for the apps to push
# -----------------------------------------------------------
printf "\n----- Waiting for apps to push ----- \n"
date
wait ${REST_PID}
wait ${APP_PID}
wait ${PLAYGROUND_PID}

export COMPLETED_STEP="4"
update_status

date
printf "\n----- Finished pushing apps ----- \n"

# -----------------------------------------------------------
# Start Composer Rest Server
# -----------------------------------------------------------
start_restserver &
export REST_PID=$!

# -----------------------------------------------------------
# Start the app
# -----------------------------------------------------------

start_app &
export APP_PID=$!

wait ${REST_PID}

export COMPLETED_STEP="5"
update_status

wait ${APP_PID}

# -----------------------------------------------------------
# Ping IBP that the application is alive  - [ Optional ]
# -----------------------------------------------------------

export APP_URL=$(cf app ${CF_APP} | grep -Po "(?<=routes:)\s*\S*")
export COMPLETED_STEP="6"
update_status

printf "\n\n --- We are done here. ---\n\n"
