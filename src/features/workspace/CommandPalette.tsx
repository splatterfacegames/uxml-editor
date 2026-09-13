import { useMemo } from 'react';
import { useSyncExternalStore } from 'react';
import {
  CommandPalette as SharedCommandPalette,
  ThemeProvider,
  type ActionPresentation,
} from '@jethac/tools-frontend-stack/ui';
import '@jethac/tools-frontend-stack/ui/styles.css';
import type { CommandRegistry } from '../../core/store/CommandRegistry';
import type { WorkspaceUiController } from './WorkspaceUiController';

export interface CommandPaletteProps {
  readonly registry: CommandRegistry;
  readonly ui: WorkspaceUiController;
}

export function CommandPalette({ registry, ui }: CommandPaletteProps) {
  const commandSnapshot = useSyncExternalStore(registry.subscribe, registry.getSnapshot, registry.getSnapshot);
  const uiSnapshot = useSyncExternalStore(ui.subscribe, ui.getSnapshot, ui.getSnapshot);
  const actions = useMemo<readonly ActionPresentation[]>(
    () => commandSnapshot.commands.map((command) => ({
      id: command.id,
      label: command.label,
      // The shared palette filters on label + aliases and treats group as
      // section metadata; carrying the category through both keeps the
      // bespoke palette's "type a category to narrow" behavior.
      aliases: [command.category],
      group: command.category,
      shortcut: command.shortcut ?? undefined,
      disabled: !command.enabled,
      onInvoke: () => {
        void registry.execute(command.id);
      },
    })),
    [commandSnapshot, registry],
  );

  return (
    <ThemeProvider theme="light">
      <SharedCommandPalette
        actions={actions}
        open={uiSnapshot.commandPaletteOpen}
        onOpenChange={(open) => {
          if (!open) ui.closeCommandPalette();
        }}
      />
    </ThemeProvider>
  );
}
