# Nightscout VPS Installer

Easily install Nightscout on a cheap VPS. Perfect for DIY diabetes management.

## What is Nightscout?

Nightscout is a powerful tool for diabetes management that:

- Displays glucose levels, insulin and carbs intake history on the same graph
- Shows information about activities, pump status and age
- Provides reports to improve Time in Range (TIR)
- Offers alerts for caregivers and shareable data for doctors

## Quick Start

1. **Get a VPS:**

   - Use [this DigitalOcean link](https://m.do.co/c/9c0cb2202c06) for $200 credit (2 months free)
   - Choose a region closest to you
   - Choose Ubuntu 24.04 (LTS) x64
   - Choose Basic, Regular, $6/month plan (1GB RAM, 1 CPU, 25GB SSD)
   - Choose "Password" for authentication (or SSH key if you're tech-savvy)
   - Enter "nightscout" as the hostname
   - Create a droplet and wait for it to boot

2. **Get a hostname:**

   - Use your own domain, or
   - Email ip@nightscout.top with your VPS IP for a free hostname (you.nightscout.top)

3. **Install Nightscout:**

   ```
   curl -sSL https://raw.githubusercontent.com/mluggy/nightscout-vps/main/setup.sh | sudo bash
   ```

   Follow the prompts to set up your instance(s)

4. **Access Nightscout:**
   - Visit `https://you.nightscout.top` and use your API secret to log in
   - Setup your initial profile based on your pump settings

## Important Notes

- Your API secret should only be used by your DIY loop
- Followers should use "readable" only tokens
- Email is required for SSL certificates

## Free Hostname Terms

Free hostnames are provided as a courtesy. They may be revoked at any time and are for non-commercial use only.

## Disclaimer

This script is provided as-is. The author is not responsible for Nightscout, the VPS, installation issues, or any medical treatment/health outcomes. Always consult your healthcare provider for medical advice.
