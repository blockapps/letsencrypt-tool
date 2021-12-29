#!/bin/bash
set -e

if [ -z "${HOST_NAME}" ]; then
  echo "HOST_NAME var is not provided. Please enter the server hostname (e.g. example.com):"
  read -r HOST_NAME
fi

sed 's/__HOST_NAME__/'"${HOST_NAME}"'/g' nginx-get-first-cert.tpl.conf > nginx-get-first-cert.conf


echo "Nginx config for letsencrypt site was created."

if [[ "${DRY_RUN}" = "true" ]]; then
  echo "DRY_RUN is TRUE - will do the dry run (staging) - for test or debugging."
  DRY_RUN_STRING="--dry-run"
else
  echo "DRY_RUN is FALSE - will execute the PRODUCTION cert request (rate limit of 5 certs/week/host)"
  DRY_RUN_STRING=""
fi

if [[ "${NON_INTERACTIVE}" = "true" ]]; then
  echo "Running non-interactively"
else
  echo "Continue with letsencrypt certificate request? Press Enter to confirm..."
  read -s -n 1 key
  if [[ $key != "" ]]; then
    exit 0
  fi
fi

if [ -z "${ADMIN_EMAIL}" ]; then
  echo "ADMIN_EMAIL var is not provided. Please enter the admin email address:"
  read -r ADMIN_EMAIL
fi

if [ -z "${DEST_PATHS}" ]; then
  echo "DEST_PATHS var is not provided. Please enter the destination directory paths, divided with comma (,):"
  read -r DEST_PATHS
fi
if [[ ${DEST_PATHS} == *"~"* ]]; then
  echo "Error: DEST_PATHS must not contain the unresolved paths with '~'. Use absolute paths. Exit"
  exit 2
fi

docker-compose up -d

function cleanup {
  docker-compose down
}

trap cleanup EXIT

docker run -it --rm \
  -v $(pwd)/letsencrypt-site:/data/letsencrypt \
  -v $(pwd)/letsencrypt-data/etc/letsencrypt:/etc/letsencrypt \
  -v $(pwd)/letsencrypt-data/var/lib/letsencrypt:/var/lib/letsencrypt \
  -v $(pwd)/letsencrypt-data/var/log/letsencrypt:/var/log/letsencrypt \
  certbot/certbot \
  certonly ${DRY_RUN_STRING} --webroot --email "${ADMIN_EMAIL}" --agree-tos --no-eff-email --webroot-path=/data/letsencrypt -d "${HOST_NAME}"

printf "\nDone.\n\n"

if [[ "${DRY_RUN}" = "true" ]]; then
  echo "See above for a dry-run result. To generate the cert - execute the normal run."
  printf "\n\n"
else
  cert_path="letsencrypt-data/etc/letsencrypt/live/${HOST_NAME}/fullchain.pem"
  key_path="letsencrypt-data/etc/letsencrypt/live/${HOST_NAME}/privkey.pem"
  echo "Cert path: ${cert_path}"
  echo "Key path: ${key_path}"
  echo "(use sudo to access)"
  printf "\n\n"

  echo "################################################"
  echo "Use these commands to copy to destination paths:"
  IFS=',' read -r -a DEST_PATHS_ARRAY <<< "${DEST_PATHS}"
  for destination in "${DEST_PATHS_ARRAY[@]}"
  do
    echo "sudo cp ${cert_path} ${destination}/server.pem"
    echo "sudo cp ${key_path} ${destination}/server.key"
  done
  printf "\n\n"
  echo "# Example command to copy to strato-getting-started:"
  echo "sudo cp ${cert_path} /datadrive/strato-getting-started/ssl/certs/server.pem"
  echo "sudo cp ${key_path} /datadrive/strato-getting-started/ssl/private/server.key"
  printf "\n\n"

  echo "Crontab command for automatic cert renewal:"
  echo "0 5 1 */2 * (PATH=\${PATH}:/usr/local/bin && cd $(pwd) && HOST_NAME=${HOST_NAME} DEST_PATHS=${DEST_PATHS} STRATOGS_DIR_PATH=/datadrive/strato-getting-started DAPP_NGINX_CONTAINER_NAME=myapp_nginx_1 ./renew-ssl-cert.sh >> $(pwd)/letsencrypt-tool-renew.log 2>&1)"
  echo "Adjust the crontab schedule (min hour day month year), STRATOGS_DIR_PATH (optional) and DAPP_NGINX_CONTAINER_NAME if executing on the machine with DApp running (optional)."

  echo "################################################"
fi
