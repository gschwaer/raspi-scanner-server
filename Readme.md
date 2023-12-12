# Raspberry Pi As Document Scanner Server

In my setup I use a *Raspberry Pi 3 Model B Rev 1.2* running *Raspbian GNU/Linux 11 (bullseye)* and I have a *Fujitsu fi-6130* connected to it via USB.

_Note:_ diffs are relative to `/etc/.`.


## Scanning Via Network (`saned`)

**Steps**

* Install `sane` (only the required non graphical tools, i.e., `sane-utils`) `sudo apt install --no-install-recommends sane-utils`
* Use `sudo scanimage -L` to localize your scanner, e.g.
  ```
  device `fujitsu:fi-6130dj:87644' is a FUJITSU fi-6130dj scanner
  ```
* Test that the scanner works `sudo scanimage -d 'fujitsu:fi-6130dj:87644' -o /tmp/test.png`
* Make sane accessible via network in `/etc/sane.d/saned.conf`
  ```diff
  diff --git a/sane.d/saned.conf b/sane.d/saned.conf
  index 664e459..f133cde 100644
  --- a/sane.d/saned.conf
  +++ b/sane.d/saned.conf
  @@ -19,6 +19,7 @@
  #
  # The hostname matching is not case-sensitive.

  +192.168.0.0/24
  #scan-client.somedomain.firm
  #192.168.0.1
  #192.168.0.1/29
  ```
  (Check `ip addr` if that fits your network config.)
* I needed a reboot here for some reason, simply restarting `saned` did not work
* Now the scanner should be available in the network for SANE clients, e.g. using *Document Scanner / simple-scan*. But on the client side we need to tell SANE where to look for the scanner. This is what we can do in `/etc/sane.d/net.conf`, just add the `.local` or `IP` address of the server. Mine looks like this:
  ```
  # This is the net backend config file.

  ## net backend options
  # Timeout for the initial connection to saned. This will prevent the backend
  # from blocking for several minutes trying to connect to an unresponsive
  # saned host (network outage, host down, ...). Value in seconds.
  # connect_timeout = 60

  ## saned hosts
  # Each line names a host to attach to.
  # If you list "localhost" then your backends can be accessed either
  # directly or through the net backend.  Going through the net backend
  # may be necessary to access devices that need special privileges.
  # localhost
  athena.local
  ```
* Fix: For me the scanner was presented to clients as two scanners for some reason, the first works the second doesn't:
  ```
  $ scanimage -L
  device `net:athena.local:fujitsu:fi-6130dj:87644' is a FUJITSU fi-6130dj scanner
  device `net:athena.local:escl:fi-6130dj:87644' is a FUJITSU fi-6130dj scanner
  ```
  It seems the scanner is erroneously detected a second time as an escl scanner. Fix:
  ```diff
  diff --git a/sane.d/dll.conf b/sane.d/dll.conf
  index cc7dfec..bdaad4b 100644
  --- a/sane.d/dll.conf
  +++ b/sane.d/dll.conf
  @@ -34,7 +34,7 @@ epjitsu
  #epson
  epson2
  epsonds
  -escl
  +#escl
  fujitsu
  genesys
  #gphoto2
  ```
* (Debug helpers: `systemctl status saned.socket`, `journalctl -f`)


## Trigger Scan With Scanner Buttons (`scanbd`)

### `saned` vs `scanbd` vs `scanbm`

The honorable `saned` does not have support for scanner button readout. This is what `scanbd` does. But `saned` and `scanbd` cannot access the scanner at the same time. For this purpose there is `scanbm` (included in the `scanbd` package). For network SANE clients `scanbm` pretends to be `saned` (uses same port) and if a connection is requested, `scanbm` pauses `scanbd` and starts `saned`. Note that when installing `sane`/`sane-utils`, systemd is set up similarly: It only launches `saned` (`saned@.service`) when the SANE network port is accessed (`saned.socket`).


**Steps**

* Install `scanbd`: `sudo apt install --no-install-recommends scanbd`
* Make sure you closed all SANE clients.
* `scanbm.socket` should have failed to start because the network port was in use by `saned.socket`, see `systemctl status scanbm.socket`
* Disabling `saned.socket` with `sudo systemctl disable saned.socket`
* For me stopping `saned.socket` and starting `scanbm.socket` did not work. I had to reboot for this to work.
* After the reboot, when pressing the Scan/Stop button on the scanner I got a `journalctl` entry
  ```
  Nov 20 21:06:40 athena scanbd[392]: /usr/sbin/scanbd: trigger action for scan for device fujitsu:fi-6130dj:87644 with script test.script
  ```
* Unfortunately that destroyed everything else again.
  1. The default `scanbm` config breaks network scanning with `saned`. Fix:
     ```diff
     diff --git a/scanbd/scanbd.conf b/scanbd/scanbd.conf
     index c2d9333..a235d52 100644
     --- a/scanbd/scanbd.conf
     +++ b/scanbd/scanbd.conf
     @@ -57,7 +57,7 @@ global {
              # the saned executable for manager-mode
              saned   = "/usr/sbin/saned"
              saned_opt  = {} # string-list
     -               saned_env  = { "SANE_CONFIG_DIR=/etc/scanbd" } # list of environment vars for saned
     +        saned_env  = { "SANE_CONFIG_DIR=/etc/sane.d" } # list of environment vars for saned

              # Scriptdir specifies where scanbd normally looks for scripts.
              # The scriptdir option can be defined as:
     ```
  2. `scanimage` is now broken when executed from command line. This is because `scanimage` tries to access the scanner directly and `scanbd` now constantly claims the scanner. Which is fine for usual operation, because `scanbd` is smart enough to stop claiming the scanner when it is executing a script due to a button press. And for SANE client scanning, `scanbd` is paused by `scanbm`. If you need to run `scanimage` on the same machine (outside of `scanbd` scripts) you can either disable `scanbd` (`sudo systemctl stop scanbd`) or make `scanimage` use the network route as well, by changing `/etc/sane.d/net.conf`
     ```diff
     diff --git a/sane.d/net.conf b/sane.d/net.conf
     index f55f29c..3a8e29b 100644
     --- a/sane.d/net.conf
     +++ b/sane.d/net.conf
     @@ -11,4 +11,4 @@
      # If you list "localhost" then your backends can be accessed either
      # directly or through the net backend.  Going through the net backend
      # may be necessary to access devices that need special privileges.
     -# localhost
     +localhost
     ```
     For that to work you will have to prefix the device name with `net:localhost:`, e.g., `scanimage -d 'net:localhost:fujitsu:fi-6130dj:87644' -o /tmp/test.png` (works without `sudo` because we don't access the hardware directly anymore).
* Next we change the `scanbd` config `/etc/scanbd/scanbd.conf` a little to our needs
  ```diff
  diff --git a/scanbd/scanbd.conf b/scanbd/scanbd.conf
  index 5d74933..c2d9333 100644
  --- a/scanbd/scanbd.conf
  +++ b/scanbd/scanbd.conf
  @@ -69,7 +69,7 @@ global {
           # scriptdir = /some/path
           # sets scriptdir to the specified absolute path
           # Default scriptdir is <path>/etc/scanbd, this is normally appropriate
  -               scriptdir = /etc/scanbd/scripts
  +        scriptdir = /etc/scanbd/

           # Scripts to execute upon device insertion/removal.
           # It can be necessary to load firmware into the device when it is first
  @@ -142,7 +142,7 @@ global {
                   # or an absolute pathname.
                   # It must contain the path to the action script without arguments
                   # Absolute path example: script = "/some/path/foo.script
  -                script = "test.script"
  +                script = "scan-to-share.sh"
           }
           action email {
                   filter = "^email$"
  ```
* We put our script `scan-to-share.sh` at `/etc/scanbd/scan-to-share.sh`. Ensure owner `root:root` and permissions `-rwxr-xr-x`.
  * Create scanner share directory (with access permissions for group `scanner`, which is used by `saned`).
    ```bash
    mkdir /srv/scanner-share
    chown root:scanner /srv/scanner-share
    chmod g+w /srv/scanner-share
    ```
  * For the script you need `img2pdf`: `sudo apt install --no-install-recommends img2pdf`
  * For more `scanimage` options, check `scanimage -d "net:localhost:fujitsu:fi-6130dj:87644" --help`
* Fix: `scanbd` pulls `openbsd-inetd | inet-superserver` as a dependency and configures it to restart `scandm`. I guess that is a remnant from pre-systemd times. Now it's quite unnecessary and spams the logs because it fails to restart `scanbm` on the `saned` port. It can be disabled by either `sudo systemctl disable inetd.service` (could shoot you in the foot if you need that for something else (later)) or by changing `/etc/inetd.conf`
  ```diff
  diff --git a/inetd.conf b/inetd.conf
  index c06bd79..84a1612 100644
  --- a/inetd.conf
  +++ b/inetd.conf
  @@ -35,5 +35,5 @@
   #:HAM-RADIO: amateur-radio services

   #:OTHER: Other services
  -sane-port stream tcp nowait saned /usr/sbin/scanbm scanbm
  +# sane-port stream tcp nowait saned /usr/sbin/scanbm scanbm

  ```
  followed by `sudo systemctl restart inetd.service`.

Ref:
* https://chrisschuld.com/2020/01/network-scanner-with-scansnap-and-raspberry-pi/
* http://howto.philippkeller.com/2018/02/08/Scan-with-raspberry-pi-convert-with-aws-to-searchable-PDF/
* https://pimylifeup.com/raspberry-pi-scanner-server/


## Access Scans Via Network Share (`samba`)

1. Setup samba for network access to the scanner-share directory.
   ```bash
   # We're doing everything as root
   sudo su
   cd
   # a) Install samba
   apt install --no-install-recommends samba
   # c) Add samba user `scanner-share-user` (with group `scanner` so it has modify permissions on the scanner share)
   useradd -M -g scanner scanner-share-user
   # d) Generate samba password for user
   #    Saved at /root/scanner-share-user.pass
   tr -dc A-Za-z0-9 </dev/urandom | head -c 32 > scanner-share-user.pass
   echo >> scanner-share-user.pass # add newline at end of file
   # e) Add samba user
   cat scanner-share-user.pass scanner-share-user.pass | smbpasswd -s -a scanner-share-user
   echo "Login"
   echo "USER: scanner-share-user"
   echo "PASS: $(cat scanner-share-user.pass)"
   echo "SERVER: $(hostname).local ($(hostname -I | sed 's/ .*//'))"
   ```
   You can use the `.local` instead of the IP address if mDNS is handled correctly in your network.
2. Add the scanner-share to the samba config
   ```diff
   diff --git a/samba/smb.conf b/samba/smb.conf
   index 6a184f9..c2b313e 100644
   --- a/samba/smb.conf
   +++ b/samba/smb.conf
   @@ -234,3 +234,10 @@
   # to the drivers directory for these users to have write rights in it
   ;   write list = root, @lpadmin

   +[scanner-share]
   +path = /srv/scanner-share
   +directory mask = 0777
   +create mask = 0777
   +writable = yes
   +public = no
   +
   ```
3. Restart samba `sudo systemctl restart smbd`
4. On the client, try to access `smb://SERVER/scanner-share/` (use `SERVER` from above), e.g., with a file explorer (nautilus/nemo/...). It should ask for a login. (Use `USER` and `PASS` from above. Domain should be `WORKGROUP` or see server's `/etc/samba/smb.conf`.)
5. (opt) Add a bookmark in your file explorer for ease of use.
6. (opt) By default samba will advertise printer drivers for windows machines in a directory named `print$`. If undesired, disable this
   ```diff
   diff --git a/samba/smb.conf b/samba/smb.conf
   index b055e0f..73b7412 100644
   --- a/samba/smb.conf
   +++ b/samba/smb.conf
   @@ -221,12 +221,12 @@

    # Windows clients look for this share name as a source of downloadable
    # printer drivers
   -[print$]
   -   comment = Printer Drivers
   -   path = /var/lib/samba/printers
   -   browseable = yes
   -   read only = yes
   -   guest ok = no
   +;[print$]
   +;   comment = Printer Drivers
   +;   path = /var/lib/samba/printers
   +;   browseable = yes
   +;   read only = yes
   +;   guest ok = no
    # Uncomment to allow remote administration of Windows print drivers.
    # You may need to replace 'lpadmin' with the name of the group your
    # admin users are members of.
   ```


Ref:
* https://pimylifeup.com/raspberry-pi-samba/
* `man smb.conf`


## Notes

* I tried to improve on the image processing done by the scanner driver using some imagemagick (see [`./test.sh`](./test.sh)). But that was too much for the Pi, so I will keep using the slightly less pretty defaults.
* I wrote some (German) labels for the different function modes that I printed and taped onto the printer ([`./Function List.ods`](./Function%20List.ods)).


## Future Work

* Maybe checkout `unpaper`
* OCR, but definitely not on the Pi. Maybe putting a script in the `scanner-share`, so the users can post process their scans.
