import { Action, ActionPanel, Alert, confirmAlert, Form, Icon, List, open, showHUD, showToast, Toast } from "@raycast/api";
import { readFileSync } from "fs";
import { homedir } from "os";
import { join } from "path";

/// Olive Lamp writes the actions of the server its panel shows here, with the token its links need. The file holds
/// no OliveTin secret: the app signs in and runs the action itself.
const CATALOG = join(homedir(), "Library/Application Support/Olive Lamp/actions.json");

interface Choice {
  value: string;
  title: string;
}

interface Argument {
  name: string;
  title: string;
  initial?: string;
  choices: Choice[];
}

interface LampAction {
  id: string;
  title: string;
  group?: string;
  section?: string;
  hold: boolean;
  reason: boolean;
  opensInBrowser: boolean;
  arguments: Argument[];
}

interface Catalog {
  version: number;
  token: string;
  server?: { id: string; name: string; address: string };
  actions?: LampAction[];
}

function readCatalog(): Catalog | undefined {
  try {
    const catalog = JSON.parse(readFileSync(CATALOG, "utf8")) as Catalog;
    return catalog.version === 1 && catalog.server && catalog.actions ? catalog : undefined;
  } catch {
    return undefined;
  }
}

/// Hands the action to Olive Lamp, which follows the run in its panel and notifies when it fails.
async function run(catalog: Catalog, action: LampAction, picks: Record<string, string> = {}, reason?: string) {
  if (action.hold) {
    const sure = await confirmAlert({
      title: `Run ${action.title}?`,
      message: "In Olive Lamp's panel this action runs only after you hold it.",
      primaryAction: { title: "Run", style: Alert.ActionStyle.Destructive },
    });
    if (!sure) return;
  }
  const query = new URLSearchParams({ token: catalog.token, server: catalog.server!.id, action: action.id });
  if (action.hold) query.set("confirmed", "1");
  if (reason !== undefined) query.set("reason", reason);
  for (const [name, value] of Object.entries(picks)) query.set(`arg.${name}`, value);
  try {
    await open(`olivelamp://run?${query.toString()}`);
    await showHUD(`${action.title} sent to Olive Lamp`);
  } catch (error) {
    await showToast({ style: Toast.Style.Failure, title: "Olive Lamp did not open", message: String(error) });
  }
}

function RunForm(props: { catalog: Catalog; action: LampAction }) {
  const { catalog, action } = props;
  return (
    <Form
      navigationTitle={action.title}
      actions={
        <ActionPanel>
          <Action.SubmitForm
            title="Run"
            icon={Icon.Play}
            onSubmit={(values: Record<string, string>) => {
              const picks: Record<string, string> = {};
              for (const argument of action.arguments) picks[argument.name] = values[`arg.${argument.name}`];
              return run(catalog, action, picks, action.reason ? values.reason : undefined);
            }}
          />
        </ActionPanel>
      }
    >
      {action.arguments.map((argument) => (
        <Form.Dropdown
          key={argument.name}
          id={`arg.${argument.name}`}
          title={argument.title}
          defaultValue={argument.initial}
        >
          {argument.choices.map((choice) => (
            <Form.Dropdown.Item key={choice.value} value={choice.value} title={choice.title} />
          ))}
        </Form.Dropdown>
      ))}
      {action.reason && <Form.TextField id="reason" title="Reason" placeholder="Why it runs now" />}
    </Form>
  );
}

function ActionItem(props: { catalog: Catalog; action: LampAction }) {
  const { catalog, action } = props;
  const accessories: List.Item.Accessory[] = [];
  if (action.hold) accessories.push({ icon: Icon.Fingerprint, tooltip: "Asks before it runs" });
  if (action.arguments.length > 0) accessories.push({ text: action.arguments.map((a) => a.title).join(", ") });
  if (action.opensInBrowser) accessories.push({ icon: Icon.Globe, tooltip: "Runs from the web page" });
  return (
    <List.Item
      title={action.title}
      subtitle={action.section}
      icon={Icon.Play}
      keywords={[action.group ?? "", action.section ?? ""].filter(Boolean)}
      accessories={accessories}
      actions={
        <ActionPanel>
          {action.opensInBrowser ? (
            <Action.OpenInBrowser title="Open in Browser" url={catalog.server!.address} />
          ) : action.arguments.length > 0 || action.reason ? (
            <Action.Push title="Run…" icon={Icon.Play} target={<RunForm catalog={catalog} action={action} />} />
          ) : (
            <Action title="Run" icon={Icon.Play} onAction={() => run(catalog, action)} />
          )}
          {!action.opensInBrowser && action.arguments.length > 0 && (
            <Action
              title="Run with Defaults"
              icon={Icon.Bolt}
              onAction={() =>
                run(
                  catalog,
                  action,
                  Object.fromEntries(action.arguments.filter((a) => a.initial).map((a) => [a.name, a.initial!])),
                )
              }
            />
          )}
          <Action.OpenInBrowser title="Open OliveTin" url={catalog.server!.address} />
        </ActionPanel>
      }
    />
  );
}

export default function Command() {
  const catalog = readCatalog();
  if (!catalog) {
    return (
      <List>
        <List.EmptyView
          icon={Icon.LightBulb}
          title="Open Olive Lamp first"
          description="Olive Lamp lists the actions of the OliveTin server its panel shows once it has read it."
        />
      </List>
    );
  }
  const groups = new Map<string, LampAction[]>();
  for (const action of catalog.actions!) {
    const group = action.group ?? "";
    groups.set(group, [...(groups.get(group) ?? []), action]);
  }
  return (
    <List navigationTitle={catalog.server!.name} searchBarPlaceholder={`Actions on ${catalog.server!.name}`}>
      {[...groups].map(([group, actions]) => (
        <List.Section key={group} title={group || undefined}>
          {actions.map((action) => (
            <ActionItem key={action.id} catalog={catalog} action={action} />
          ))}
        </List.Section>
      ))}
    </List>
  );
}
