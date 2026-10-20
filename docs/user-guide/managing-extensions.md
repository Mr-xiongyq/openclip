# Managing extensions and custom actions

You can install community extensions and make your own search or script actions, either from the app or by dropping files into a folder.

## Extension Store

The Extension Store is in **Preferences > Extension Store**. You can browse official and community extensions, read each one's details, actions, and author, and click **Install** to add it.

### How remote installation works

1. `ExtensionsAPIClient` fetches the published extensions catalog.
2. `RemoteExtensionInstaller` downloads the extension's `.zip` or `.openclipext` bundle.
3. [`ExtensionManager.installExtension(from:)`](../../Sources/Core/Extensions/ExtensionManager.swift) extracts and verifies it in `~/.openclip/extensions/`.
4. `ExtensionManager` reloads the catalog and registers the new actions with `ActionRegistry`.

The official and community catalog is published from the open [`openclip-extensions`](https://github.com/ganeshmshetty/openclip-extensions) repository, which holds its builds, releases, and download stats. The app and the store only talk to the extension store API. If you write extensions, clone that repository into `Extensions/` inside the app checkout. It is a separate clone, not a git submodule.

## Installing by hand

Put extensions or standalone scripts in your local extensions folder:

```bash
~/.openclip/extensions/
```

Three kinds of file work there:

- An extension bundle (`.openclipext`) is a folder with `manifest.json` and its code.
- A `.zip` archive of an extension. `ExtensionManager` unzips it for you.
- A standalone script (`.sh`, `.py`, `.js`, or `.applescript`) with its metadata in a comment header.

## Creating custom actions in the app

You can make a web search link or an inline shell script without writing a manifest:

1. Open **Preferences > Actions**.
2. Click **+ Add Custom Action**.
3. Pick the type:
   - **URL Template**: a title, an SF Symbol icon, and a URL such as `https://google.com/search?q={query}`.
   - **Shell Script**: a command or short script, such as `tr '[:lower:]' '[:upper:]'`.
4. Click **Save**.

### Where custom actions are stored

[`CustomActionManifestWriter`](../../Sources/OpenClip/Platform/Extensions/CustomActionManifestWriter.swift) writes each custom action as a one-action manifest package at `~/.openclip/extensions/<id>/openclip.json`. It loads through the same scan as installed extensions. `~/Library/Application Support` isn't used, and `custom_actions.json` and `CustomActionManager` are retired.
