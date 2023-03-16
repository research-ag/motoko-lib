# Setup

Install VS Code and Motoko extension.

Install `dfx` ([more](https://github.com/dfinity/sdk)):

```
sh -ci "$(curl -fsSL https://internetcomputer.org/install.sh)"
```

Install `vessel` ([more](https://github.com/dfinity/vessel)), substitute version with the latest:

```
cd $HOME/bin
wget https://github.com/dfinity/vessel/releases/download/v0.6.4/vessel-linux64
mv vessel-linux64 vessel
chmod +x vessel
```

Install `ic-repl` ([more](https://github.com/chenyan2002/ic-repl)), substitute version with the latest:
```
cd $HOME/bin
wget https://github.com/chenyan2002/ic-repl/releases/download/0.3.17/ic-repl-linux64
mv ic-repl-linux64 ic-repl
chmod +x ic-repl
```

Install `make`:

```
sudo apt install make
```

Install `mkdocs` ([more](https://www.mkdocs.org/user-guide/installation/)):

```
pip install mkdocs
```