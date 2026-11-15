# Olive Lamp for Raycast

Run your OliveTin actions from Raycast through [Olive Lamp](https://github.com/DabuSoft-pl/olive-lamp), the menu bar
app for OliveTin.

**Run OliveTin Action** lists the actions of the server Olive Lamp's panel shows, in their groups. Actions with choices
open a form; an action Olive Lamp runs only after a hold asks you first here. Olive Lamp then starts the action, follows
it in its panel and notifies you when it fails.

The extension reads `~/Library/Application Support/Olive Lamp/actions.json`, which Olive Lamp writes for it. It holds
no OliveTin secret: the app signs in and runs the action. Links carry a token from that file, so a web page cannot
start an action through `olivelamp://`.

## Develop

```bash
npm install
npm run dev     # loads it into Raycast
npm run build
```
