#!/bin/bash

# Base domain for default hostnames
BASE_DOMAIN="nightscout.top"

# Function to generate a random API Secret
generate_api_secret() {
    tr -dc A-Za-z0-9 </dev/urandom | head -c 12 ; echo ''
}

# Function to emphasize user prompts
bold_text() {
    echo -e "\033[1m$1\033[0m"
}

# Function to convert string to kebab case
kebab_text() {
    echo "$1" | sed -e 's/[^[:alnum:]]/-/g' | tr '[:upper:]' '[:lower:]' | tr -s '-' | sed -e 's/^-//' -e 's/-$//'
}

# Function to normalize user input for yes/no prompts
normalize_yes_no() {
    case "$1" in
        y|Y|yes|Yes|YES) echo "y" ;;
        n|N|no|No|NO) echo "n" ;;
        *) echo "" ;;
    esac
}

# Function to get existing value from docker-compose.yml
get_existing_value() {
    local key=$1
    local file=${2:-docker-compose.yml}
    [[ -f "$file" ]] && grep "$key" "$file" | sed -E "s/.*$key='?([^'\"]+)'?.*/\1/" | tr -d "'" || echo ""
}

# Function to prompt for input with existing value
prompt_with_existing() {
    local prompt=$1
    local existing=$2
    local var_name=$3
    
    if [[ -n "$existing" ]]; then
        read -p "$(bold_text "$prompt (press Enter to keep $existing): ")" user_input
        eval "$var_name=\${user_input:-$existing}"
    else
        read -p "$(bold_text "$prompt: ")" "$var_name"
    fi
}

# Function to get existing email from docker-compose.yml
get_existing_email() {
    [[ -f docker-compose.yml ]] && grep "certificatesresolvers.le.acme.email=" docker-compose.yml | sed -E "s/.*email=([^'\"]+).*/\1/" || echo ""
}

# Function to get existing Nightscout instance names
get_existing_instance_names() {
    if [[ -f docker-compose.yml ]]; then
        (grep "traefik.http.routers.nightscout_" docker-compose.yml 2>/dev/null || echo "") | 
        sed -E "s/.*nightscout_([^.]+).rule=Host.*/\1/" | 
        sort | uniq | 
        grep -v "^[[:space:]]*-"
    fi
    
    # Add instances from the current session
    for instance in "${nightscout_instances[@]}"; do
        IFS=':' read -r ns_name _ _ <<< "$instance"
        echo "$ns_name"
    done | sort | uniq
}

# Function to get existing API secret for a Nightscout instance
get_existing_api_secret() {
    local instance_name=$1
    [[ -f docker-compose.yml ]] && awk -v name="nightscout_$instance_name:" '
        $0 ~ name {flag=1; next}
        flag && /API_SECRET:/ {
            match($0, /API_SECRET: *([^ ]+)/, arr)
            gsub(/^["\047]|["\047]$/, "", arr[1])  # Remove leading/trailing quotes
            print arr[1]
            exit
        }
    ' docker-compose.yml || echo ""
}

# Function to get existing hostname for a Nightscout instance
get_existing_hostname() {
    local instance_name=$1
    [[ -f docker-compose.yml ]] && grep -A5 "nightscout_$instance_name:" docker-compose.yml | grep "traefik.http.routers" | sed -E "s/.*Host\(\`([^']+)\`\).*/\1/" || echo ""
}

# Ask for the user's email address
existing_email=$(get_existing_email)
prompt_with_existing "Please enter your email address" "$existing_email" user_email

# Remove conflicting packages and install Docker
sudo apt -y remove docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc
sudo apt-get update
sudo apt-get install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt update -y
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Ensure Docker service is enabled and running
sudo systemctl enable docker
sudo systemctl start docker

# Initialize an array to store Nightscout instances
declare -a nightscout_instances

# Function to prompt for Nightscout instance details
prompt_nightscout_instance() {
    while true; do
        existing_names=$(get_existing_instance_names)
        if [[ -n "$existing_names" ]]; then
            echo "Existing Nightscout instances:"
            echo "$existing_names"
            prompt_with_existing "Enter the Nightscout instance name or a new one${1:- (mandatory)}" "" ns_name
        else
            prompt_with_existing "Enter the Nightscout instance name${1:- (mandatory)}" "" ns_name
        fi
        ns_name=$(kebab_text "$ns_name")
        
        if [[ -n "$ns_name" ]]; then
            existing_hostname=$(get_existing_hostname "$ns_name")
            default_hostname="${ns_name}.${BASE_DOMAIN}"
            prompt_with_existing "Enter the hostname for $ns_name" "${existing_hostname:-$default_hostname}" ns_hostname
            
            existing_api_secret=$(get_existing_api_secret "$ns_name")
            if [[ -n "$existing_api_secret" ]]; then
                prompt_with_existing "Enter API Secret for $ns_name" "$existing_api_secret" api_secret
            else
                api_secret=$(generate_api_secret)
                echo "$(bold_text "Generated API Secret for $ns_name: $api_secret")"
                read -p "$(bold_text "Press Enter to keep this API Secret or type a new one: ")" user_api_secret
                api_secret=${user_api_secret:-$api_secret}
            fi

            # Validate API Secret length
            while [[ ${#api_secret} -lt 12 ]]; do
                echo "$(bold_text 'API Secret must be at least 12 characters long. Please try again.')"
                read -p "$(bold_text 'Enter your desired API Secret (minimum 12 characters): ')" api_secret
            done

            # Add instance to the array
            nightscout_instances+=("$ns_name:$ns_hostname:$api_secret")
            break
        elif [[ -z "$1" ]]; then
            echo "$(bold_text 'Instance name cannot be empty. Please try again.')"
        fi
    done
}

# Prompt for at least one instance
prompt_nightscout_instance " (mandatory)"

# Ask if user wants to add more instances
while true; do
    read -p "$(bold_text 'Do you want to add another Nightscout instance? (Y/n): ')" add_more
    add_more=${add_more:-y}
    add_more=$(normalize_yes_no "$add_more")
    if [[ "$add_more" != "y" ]]; then
        break
    fi
    prompt_nightscout_instance
done

# Generate docker-compose.yml at the end
generate_docker_compose() {
    # Create the initial structure with common configurations
    cat << EOF > docker-compose.yml
version: '3'

x-logging: &default-logging
  options:
    max-size: '10m'
    max-file: '5'
  driver: json-file

x-nightscout-common: &nightscout-common
  image: nightscout/cgm-remote-monitor:latest
  restart: always
  depends_on:
    - mongo
  logging: *default-logging
  environment: &nightscout-env
    NODE_ENV: production
    TZ: Etc/UTC
    INSECURE_USE_HTTP: 'true'
    ENABLE: careportal cage basal iob sage treatmentnotify rawbg alexa cors basalprofile pushover bgi loop iage cob food direction speech bage upbat googlehome errorcodes openaps pump reservoir battery clock status device openapsbasal status-symbol status-label meal-assist freq rssi override ar2 ar2_cone_factor
    AUTH_DEFAULT_ROLES: denied

services:
  mongo:
    image: mongo:4.4
    volumes:
      - ./mongo-data:/data/db:cached
    logging: *default-logging

EOF

    # Add Nightscout instances
    for instance in "${nightscout_instances[@]}"; do
        IFS=':' read -r ns_name ns_hostname api_secret <<< "$instance"
        cat << EOF >> docker-compose.yml
  nightscout_$ns_name:
    <<: *nightscout-common
    container_name: nightscout_$ns_name
    labels:
      - 'traefik.enable=true'
      - 'traefik.http.routers.nightscout_$ns_name.rule=Host(\`$ns_hostname\`)'
      - 'traefik.http.routers.nightscout_$ns_name.entrypoints=websecure'
      - 'traefik.http.routers.nightscout_$ns_name.tls.certresolver=le'
    environment:
      <<: *nightscout-env
      MONGO_CONNECTION: mongodb://mongo:27017/$ns_name
      API_SECRET: $api_secret

EOF
    done

    # Add Traefik service
    cat << EOF >> docker-compose.yml
  traefik:
    image: traefik:latest
    container_name: 'traefik'
    command:
      - '--providers.docker=true'
      - '--providers.docker.exposedbydefault=false'
      - '--entrypoints.web.address=:80'
      - '--entrypoints.web.http.redirections.entrypoint.to=websecure'
      - '--entrypoints.websecure.address=:443'
      - "--certificatesresolvers.le.acme.httpchallenge=true"
      - "--certificatesresolvers.le.acme.httpchallenge.entrypoint=web"
      - '--certificatesresolvers.le.acme.storage=/letsencrypt/acme.json'
      - '--certificatesresolvers.le.acme.email=$user_email'
      - '--api.insecure=true'
    ports:
      - '443:443'
      - '80:80'
    volumes:
      - './letsencrypt:/letsencrypt'
      - '/var/run/docker.sock:/var/run/docker.sock:ro'
    logging: *default-logging
EOF
}

# Generate the docker-compose.yml file
generate_docker_compose

# Recreate Docker services
sudo docker compose down
sudo docker compose up -d