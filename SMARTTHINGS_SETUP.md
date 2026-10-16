# Turning the TV on with SmartThings

Controlinho can switch your TV on through Samsung's SmartThings cloud. This works even when the TV's local network connection is asleep, so it's a backup for the Wake-on-LAN signal. It's a one-time setup of about 15 minutes.

You'll need:

- Your TV added to the **SmartThings** app on your phone, under the Samsung account you'll sign in with.
- A Mac with [Homebrew](https://brew.sh).

## 1. The redirect page

SmartThings only sends you back after login to an `https://` address. The page in [`oauth-redirect/index.html`](oauth-redirect/index.html) catches that and forwards you into the app. This repository already hosts it with GitHub Pages at:

```
https://robhouseblues.github.io/controlinho-ios/oauth-redirect/
```

Use that URL **exactly, including the trailing slash**. You'll enter it twice below, and both must match character for character.

> **Using a fork?** Turn on GitHub Pages for your fork (**Settings › Pages**, *Deploy from a branch*, `main`, `/ (root)`) and use `https://<your-github-username>.github.io/<repo-name>/oauth-redirect/` instead. The page only forwards the sign-in result to the app, so it never sees your client secret.

## 2. Create the SmartThings app

Install the SmartThings command-line tool:

```bash
brew install smartthingscommunity/smartthings/smartthings
```

Then create the app:

```bash
smartthings apps:create
```

The first time you run it, a browser window opens so you can log in to your Samsung account. Answer the prompts like this:

| Prompt | Answer |
| --- | --- |
| What kind of app? | **OAuth-In App** |
| Display Name | `Controlinho` |
| Description | `iPhone remote for my TV` |
| Icon Image URL | leave empty |
| Target URL | leave empty |
| Scopes | select **r:devices:\*** and **x:devices:\*** |
| Redirect URIs | add the redirect page URL from step 1, then finish |

At the end it prints an **OAuth Client Id** and **OAuth Client Secret**. Copy both somewhere safe right away. The secret is only shown once. If you lose it, run `smartthings apps:oauth:generate` to get a new one.

## 3. Connect the app

1. Open Controlinho, tap **⋯ › TV Settings**, then **Set up SmartThings**.
2. Enter the Client ID, Client Secret and the redirect URL from step 1, then tap **Save**.
3. Tap **Sign in with Samsung account** and log in.
4. Tap **Choose TV** and pick your TV. If you only have one, it's picked for you.
5. With the TV off, tap **Turn TV on now** to test it.

From now on, the remote's **Power** button uses SmartThings and the Wake-on-LAN signal together whenever the TV is off.

## Good to know

- **Staying signed in:** each sign-in lasts about a month and renews every time you open the app. If you don't open Controlinho for a month, you'll be asked to sign in again.
- **"Power On with Mobile"** should still be turned on in the TV's settings. SmartThings needs it on many models too.
- **If sign-in fails with an error about the redirect,** the URL in the app and the one registered with SmartThings don't match exactly. Check the trailing slash. To see what's registered, run `smartthings apps:oauth`.
- **If `apps:create` fails with a 403 error,** run `smartthings logout` and then `smartthings apps:create` again so it logs in through the browser.
- **Your credentials** are stored in the iPhone's Keychain, never in the project's source code.
