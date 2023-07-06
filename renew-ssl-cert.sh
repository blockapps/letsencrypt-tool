#!/bin/bash
set -e

if ! docker-compose -v &> /dev/null
then
    echo -e "${Red}Error: docker-compose is required: https://docs.docker.com/compose/install/"
    exit 2
else
  if ! docker compose version &> /dev/null
  then
    docker_compose="docker-compose"
  else
    docker_compose="docker compose"
  fi
fi

if [ -z "${HOST_NAME}" ]; then 
  echo "HOST_NAME var is not provided. Please enter the server hostname (e.g. example.com):"
  read -r HOST_NAME
fi

if [[ "${DRY_RUN}" = "true" ]]; then
  echo "DRY_RUN is TRUE - will do the dry run - for test or debugging"
  DRY_RUN_STRING="--dry-run"
else
  echo "DRY_RUN is FALSE - will execute the PRODUCTION cert request (subject for rate limit of 5 certs/week/host)"
  DRY_RUN_STRING=""
fi

if [ -z "${DEST_PATHS}" ]; then 
  echo "DEST_PATHS var is not provided. Please enter the destination directory paths, divided with comma (,):"
  read -r DEST_PATHS
fi
if [[ ${DEST_PATHS} == *"~"* ]]; then
  echo "Error: DEST_PATHS must not contain the unresolved paths with '~'. Use absolute paths. Exit"
  exit 2
fi

# Strato-getting-started dir path is provided separately because it uses the subdirs structure for key and pem files
if [[ -n "${STRATOGS_DIR_PATH}" ]]; then
  echo "STRATOGS_DIR_PATH is set to '${STRATOGS_DIR_PATH}'"
  if [[ ! -d "${STRATOGS_DIR_PATH}" ]]; then
    echo "Error: Directory ${STRATOGS_DIR_PATH} not found. Exit."
    exit 1
  fi
else
  echo "WARNING: strato-getting-started default path does not exist. SSL cert/key won't be updated to be used for future STRATO-GS deployments."
  STRATOGS_DIR_PATH=''
fi

if [ -z "${STRATO_NGINX_CONTAINER_NAME}" ]; then 
  echo "WARNING: STRATO_NGINX_CONTAINER_NAME var is not provided. Will NOT attempt to update the cert in STRATO nginx container."
fi

if [ -z "${VAULT_NGINX_CONTAINER_NAME}" ]; then 
  echo "WARNING: VAULT_NGINX_CONTAINER_NAME var is not provided. Will NOT attempt to update the cert in Vault's nginx container."
fi

if [ -z "${DAPP_NGINX_CONTAINER_NAME}" ]; then 
  echo "WARNING: DAPP_NGINX_CONTAINER_NAME var is not provided. Will NOT attempt to update the cert in DApp's nginx container."
fi


# Stop the container that is using port 80
CONTAINER_USING_PORT_80=$(sudo docker ps | grep "0.0.0.0:80->" | awk '{print $NF}')
if [ -n "${CONTAINER_USING_PORT_80}" ]; then
  docker stop "${CONTAINER_USING_PORT_80}" || true
fi


# Start letsencrypt nginx
${docker_compose} up -d

function cleanup {
  ${docker_compose} down
  if [ -n "${CONTAINER_USING_PORT_80}" ]; then
    docker start "${CONTAINER_USING_PORT_80}" || true
  fi
}

trap cleanup EXIT

# Renew
docker run -i --rm \
  -v $(pwd)/letsencrypt-site:/data/letsencrypt \
  -v $(pwd)/letsencrypt-data/etc/letsencrypt:/etc/letsencrypt \
  -v $(pwd)/letsencrypt-data/var/lib/letsencrypt:/var/lib/letsencrypt \
  -v $(pwd)/letsencrypt-data/var/log/letsencrypt:/var/log/letsencrypt \
  certbot/certbot \
  renew ${DRY_RUN_STRING} --force-renewal --no-random-sleep-on-renew

printf "\nDone.\n\n"

if [[ "${DRY_RUN}" = "true" ]]; then
  echo "See above for a dry-run result. To actually renew the cert - execute the normal run."
  printf "\n\n"
else
  # Copy the new certs
  cert_path="letsencrypt-data/etc/letsencrypt/live/${HOST_NAME}/fullchain.pem"
  key_path="letsencrypt-data/etc/letsencrypt/live/${HOST_NAME}/privkey.pem"
    
  echo "Cert path: ${cert_path}"
  echo "Key path: ${key_path}"
    
  echo "Copying to destination paths:"
  IFS=',' read -r -a DEST_PATHS_ARRAY <<< "${DEST_PATHS}"
  for destination in "${DEST_PATHS_ARRAY[@]}"
  do
    echo "Destination path: ${destination}"
    set -x
    sudo cp ${cert_path} ${destination}/server.pem
    sudo cp ${key_path} ${destination}/server.key
    set +x
  done
  printf "\n\n"
  
  if [[ -n "${STRATOGS_DIR_PATH}" ]]; then
    echo "Copying key and cert to the strato-getting-started ssl dir..."
    set -x
    sudo cp ${cert_path} ${STRATOGS_DIR_PATH}/ssl/certs/server.pem
    sudo cp ${key_path} ${STRATOGS_DIR_PATH}/ssl/private/server.key
    set +x
  fi


  echo "Copying key and cert to the live docker containers and reloading their configs..."
  set -x
  if [ -n "${STRATO_NGINX_CONTAINER_NAME}" ]; then
    sudo docker cp --follow-link ${cert_path} ${STRATO_NGINX_CONTAINER_NAME}:/etc/ssl/certs/server.pem
    sudo docker cp --follow-link ${key_path} ${STRATO_NGINX_CONTAINER_NAME}:/etc/ssl/private/server.key
    sudo docker exec ${STRATO_NGINX_CONTAINER_NAME} openresty -s reload
  fi
  if [ -n "${VAULT_NGINX_CONTAINER_NAME}" ]; then
    sudo docker cp --follow-link ${cert_path} ${VAULT_NGINX_CONTAINER_NAME}:/etc/ssl/certs/server.pem
    sudo docker cp --follow-link ${key_path} ${VAULT_NGINX_CONTAINER_NAME}:/etc/ssl/private/server.key
    sudo docker exec ${VAULT_NGINX_CONTAINER_NAME} openresty -s reload
  fi
  if [ -n "${DAPP_NGINX_CONTAINER_NAME}" ]; then
    sudo docker cp --follow-link ${cert_path} ${DAPP_NGINX_CONTAINER_NAME}:/etc/ssl/server.pem
    sudo docker cp --follow-link ${key_path} ${DAPP_NGINX_CONTAINER_NAME}:/etc/ssl/server.key
    sudo docker exec ${DAPP_NGINX_CONTAINER_NAME} nginx -s reload
  fi
  set +x

  echo "Certs have been successfully renewed. No more actions required. See output above."
  printf "\n\n"
fi
