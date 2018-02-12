# eppsa-infrastructure
Configuration of routers, servers, etc ...

## Usage
- Install openWRT on your router

- Set up root password in LuCi at [http://192.168.1.1](http://192.168.1.1)

- Set variables in ```./configure_router.sh``` especially ```SSH_PUBKEY``` if you don't want to lock yourself out.

- Apply configuration

```bash
scp ./configure_router.sh root@192.168.1.1:/root/
ssh root@192.168.1.1 chmod +x configure_router.sh
ssh root@192.168.1.1 ./configure_router.sh
```
