import { useState, useSyncExternalStore } from 'react';
import { Modal, ThemeProvider } from '@jethac/tools-frontend-stack/ui';
import type { ExternalChangeDecision } from '../../core/persistence/SaveCoordinator';
import type { FileWorkflowPort } from './FileWorkflow';

export interface ExternalChangeDialogProps {
  readonly workflow: FileWorkflowPort;
}

export function ExternalChangeDialog({ workflow }: ExternalChangeDialogProps) {
  const snapshot = useSyncExternalStore(workflow.subscribe, workflow.getSnapshot, workflow.getSnapshot);
  const [busyPath, setBusyPath] = useState<string | null>(null);
  const resolve = async (path: string, decision: ExternalChangeDecision) => {
    setBusyPath(path);
    try {
      await workflow.resolveExternalChange(path, decision);
    } finally {
      setBusyPath(null);
    }
  };
  const firstChange = snapshot.externalChanges[0];

  return (
    // ThemeProvider supplies the --atelier-color-* variables the stack's modal
    // chrome paints with; the app's own surface rules still win on the parts
    // .external-change-dialog styles.
    <ThemeProvider theme="light">
      <Modal
      isOpen={firstChange !== undefined}
      aria-label="External file changes"
      onClose={() => {
        if (firstChange !== undefined && busyPath === null) void resolve(firstChange.path, 'cancel');
      }}
      closeOnOverlayClick={false}
      showCloseButton={false}
      // 3xl's inline max-width (768px) stays above our 680px stylesheet width,
      // so the app's sizing wins without fighting the inline style.
      size="3xl"
      className="external-change-dialog"
    >
      <header>
        <h2>External File Changes</h2>
      </header>
      <div className="external-change-list">
        {snapshot.externalChanges.map((change, index) => (
          <div className="external-change-row" key={change.path}>
            <div>
              <strong>{change.path}</strong>
              <span>{change.external === 'deleted' ? 'Deleted outside the editor' : 'Changed outside the editor'}</span>
            </div>
            <div className="external-change-actions">
              <button
                autoFocus={index === 0}
                type="button"
                disabled={busyPath !== null}
                aria-label={`Reload ${change.path} from disk`}
                onClick={() => void resolve(change.path, 'reload')}
              >
                Reload from Disk
              </button>
              <button
                type="button"
                disabled={busyPath !== null}
                aria-label={`Overwrite ${change.path} on disk`}
                onClick={() => void resolve(change.path, 'overwrite')}
              >
                Keep Editor Version
              </button>
              <button
                type="button"
                disabled={busyPath !== null}
                aria-label={`Dismiss ${change.path} external change`}
                onClick={() => void resolve(change.path, 'cancel')}
              >
                Dismiss
              </button>
            </div>
          </div>
        ))}
      </div>
      </Modal>
    </ThemeProvider>
  );
}
