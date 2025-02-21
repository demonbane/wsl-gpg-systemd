# wsl-gpg-systemd
wsl-gpg-systemd is a tool to allow you to easily access your Windows-based GPG keychain and GPG ssh agent from inside a WSL instance. While there are tutorials available for using some combination of `socat`, [wsl-ssh-pageant](https://github.com/benpye/wsl-ssh-pageant)/[wsl2-ssh-pageant](https://github.com/BlackReloaded/wsl2-ssh-pageant), and [npiperelay](https://github.com/jstarks/npiperelay), they are a hassle to set up and very prone to breakage in my experience. wsl-gpg-systemd allows for new systemd-enabled WSL instances to easily allow access to both gpg-agent and the gpg-agent.ssh within WSL using only an updated version of [npiperelay](https://github.com/albertony/npiperelay) by [@albertony](https://github.com/albertony).

## Installation
Installation is done entirely from within your WSL session. Since Windows executables have to reside on the Windows filesystem, the installer will download npiperelay and place it in `%APPDATA%/npiperelay/npiperelay_windows_amd64.exe` by default.

```
git clone https://github.com/demonbane/wsl-gpg-systemd
cd wsl-gpg-systemd
./install
```

If you'd prefer to do it yourself without running the installer, you can simply copy all of the systemd units into `$HOME/.config/systemd/user` and edit the paths manually. Be sure that `enable-win32-openssh-support` is in your gpg-agent.conf in Windows.

## Options
```
Usage: install [-hgv]
Install wsl-gpg-systemd automatically. See README for manual instructions.

  -h, --help      this help
  -g, --gh        use GitHub CLI to fetch npiperelay, installing it first if necessary
  -v, --verbose   show verbose output when available
```

## How it works
npiperelay does most of the heavy lifting. It allows us to access named pipes and gpg4win Assuan "sockets" and relay them through STDIN/STDOUT to WSL. systemd then creates a "systemd socket" using the `inetd` compatibility mode (`Accept=true`) which allows it to relay STDIN/STDOUT from npiperelay into a regular Unix socket. Previous versions of this approach used `socat` as the glue between the socket and npiperelay, but with WSL now supporting systemd it is much easier and more reliable to use systemd sockets instead.

gpg4win chose to use a unique "socket" approach on Windows, where the "socket" is just a plain file containing a nonce (i.e. a password) and a TCP port number. Thanks to the [changes](https://github.com/jstarks/npiperelay/issues/1) provided by [@NZSmartie](https://github.com/NZSmartie), npiperelay can read this file, get the nonce, and connect to the TCP socket. While it would be possible to access this file and the connection information from within WSL, the TCP connection is only available on localhost on Windows, so it would require dynamically forwarding that port from Windows into the WSL environment, which would have to be done from within Windows and would just introduce another point of failure.

gpg-agent.ssh, on the other hand, is meant to be compatible with the Windows OpenSSH server, so it uses native Windows named pipes. These are not accessible inside WSL at all, so npiperelay connects to the pipe (`//./pipe/openssh-ssh-agent`), and then relays it over STDIN/STDOUT.

## Notes
* By default, WSL will be given access to the `gpg-agent.extra` socket as this is the recommended approach for "remote" systems. The extra socket does have a few restrictions, notably that `gpg --card-status` will not work. If you require this functionality you can simply edit `$HOME/.config/systemd/user/gpg-agent@.service` and change `S.gpg-agent.extra` to `S.gpg-agent` in the Windows path.
* The version of npiperelay being used is from an updated version of the original npiperelay project maintained by [@albertony](https://github.com/albertony). The changes implemented to make this possible are the work of [@NZSmartie](https://github.com/NZSmartie), [@Lexicality](https://github.com/Lexicality), [@ndimiduk](https://github.com/ndimiduk), and [@SunMar](https://github.com/SunMar).
