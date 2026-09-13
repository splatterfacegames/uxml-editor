import { expect, test, type Page } from '@playwright/test';

/**
 * Visual-regression baselines.
 *
 * Baselines live in `visual.spec.ts-snapshots/` and are platform-specific —
 * Windows captures end in `-win32.png`, Linux in `-linux.png`. A platform
 * without a committed baseline writes one on first run
 * (`updateSnapshots: 'missing'` in playwright.config.ts) instead of failing;
 * once committed, every later run compares against it.
 *
 * The captures are deliberately small in scope: one whole-workbench shot and
 * one canvas-only shot of the same fixture. `caret: 'hide'` and
 * `animations: 'disabled'` remove the two nondeterministic inputs the app
 * controls; anything else that moves a pixel is a real change to review.
 */

test('menu fixture workbench matches its baseline', async ({ page }) => {
  await openMenuProject(page);
  await expect(page).toHaveScreenshot('menu-workbench.png', {
    animations: 'disabled',
    caret: 'hide',
  });
});

test('menu fixture canvas render matches its baseline', async ({ page }) => {
  await openMenuProject(page);
  await expect(page.getByTestId('canvas-pane')).toHaveScreenshot('menu-canvas.png', {
    animations: 'disabled',
    caret: 'hide',
  });
});

async function openMenuProject(page: Page): Promise<void> {
  await page.setViewportSize({ width: 1366, height: 768 });
  await page.addInitScript(() => window.localStorage.clear());
  await page.goto('/tests/e2e/fixtures/editor.html');
  await expect(page.getByRole('application', { name: 'UXML Editor' })).toBeVisible();
  await page.getByRole('button', { name: 'Open Project' }).click();
  await expect(page.getByLabel('Project status')).toContainText('Menu Fixture');
  // The preview finishes when the fixture's authored text is on screen —
  // waiting on it rather than a timer keeps the capture deterministic.
  await expect(page.getByTestId('canvas-pane').getByText('Main Menu')).toBeVisible();
  await expect(page.getByTestId('canvas-pane').getByText('Play & Go')).toBeVisible();
}
