# eppsa-infrastructure
Configuration of routers, servers, etc ...

## Usage
- Install openWRT on your router

- Set up root password in LuCi at [http://192.168.1.1](http://192.168.1.1)

- Set variables in ```./configure_router.sh``` especially ```SSH_PUBKEY``` if you don't want to lock yourself out.

- Apply configuration

```bash
ssh root@192.168.1.1 opkg update
ssh root@192.168.1.1 opkg install rsync
ssh root@192.168.1.1 mkdir eppsa-infrastructure
rsync -av --exclude .git ./ root@192.168.1.1:eppsa-infrastructure
ssh root@192.168.1.1 chmod +x /root/eppsa-infrastructure/configure_router.sh
ssh root@192.168.1.1 /root/eppsa-infrastructure/configure_router.sh
```

## Configure captive portal
- Set variables in ```./captive_portal```

- Apply configuration

```bash
ssh root@192.168.1.1 cd eppsa-infrastructure/captive_portal
ssh root@192.168.1.1 chmod +x /root/eppsa-infrastructure/captive_portal/captive_portal.sh
ssh root@192.168.1.1 /root/eppsa-infrastructure/captive-portal/captive_portal.sh
```
