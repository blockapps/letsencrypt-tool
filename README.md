# BlockApps Letsencrypt Tool

Tool to obtain and auto-renew the SSL certificates for any DNS name that you have access to, within seconds.

This tool is a set of helper scripts for Let's Encrypt nonprofit Certificate Authority tool.

For more information refer to https://letsencrypt.org

## How to use

To run the webserver we need the first (initial) certificate to provide it to the container. 
After that, when the webserver is already running, the certificate can be auto-renewed programmatically (see "Setup auto-renewal")

### Get first cert

```
cd letsencrypt-tool
sudo HOST_NAME=mydnsname.example.com ADMIN_EMAIL=admin@example.com DEST_PATHS='/datadrive/letsencrypt-ssl' ./get-first-cert.sh
```
- HOST_NAME - used for letsencrypt certbot to do the DNS name check
- ADMIN_EMAIL - email used by letsencrypt to send notifications if auto-renewal wasn't successful (provide the real one)
- DEST_PATHS - the string with comma-separated destinations where .pem and .key should be copied (corresponding cp commands will be outputted for convenience, but not executed)
- Add the `DRY_RUN=true` var if running for test/debugging (certbot requests is subject for rate limit of 5 certs/week/host in non-dry-run mode)

In case of the successful non-dry run - copy and execute the commands provided in the end of terminal output to copy certs to final destinations

Save the line to be added to crontab (under "Crontab command for automatic cert renewal") for the "Setup auto-renewal" step.

### Setup auto-renewal

Setup the crontab job to renew the cert automatically every 2 months (cert is valid for 3 months)
```
sudo crontab -e
```
Append the command line saved from the previous step.

The line should look like the following example:
```
0 6 2 */2 * (PATH=${PATH}:/usr/local/bin && cd /PATH/TO/letsencrypt-tool && HOST_NAME=mydnsname.example.com DEST_PATHS=/datadrive/letsencrypt-ssl STRATOGS_DIR_PATH=/PATH/TO/strato-getting-started DAPP_NGINX_CONTAINER_NAME=myapp_nginx_1 ./renew-ssl-cert.sh >> /PATH/TO/letsencrypt-tool/letsencrypt-tool-renew.log 2>&1)
```
(meaning this command will run at 6:00am UTC on the 2nd day of every 2 months)

In addition to configuration vars used in first step we have 2 more in the command above:
- STRATOGS_DIR_PATH (optional) - the directory path of strato-getting-started to replace .pem and .key files under it. Cannot be provided in DEST_PATHS as it uses the additional subdirectory structure. Useful when executing on hosts with manually deployed STRATO.
- DAPP_NGINX_CONTAINER_NAME (optional) - the name of the application's nginx container to replace .pem and .key files in it and reload nginx config. Useful when executing on hosts with STRATO Application running on it.

It is **strongly recommended** testing the crontab job by **temporary** adjusting schedule to execute in the nearest minutes and checking the resulting log file.
Don't forget to revert the temporary crontab changes after.


*Created by Nikita Mendelbaum @ BlockApps (nikitam@blockapps.net)*
