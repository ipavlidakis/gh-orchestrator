const button = document.querySelector('.copy-button');
const commands = document.querySelector('#install-command');
const status = document.querySelector('#copy-status');

button.hidden = false;
button.addEventListener('click', async () => {
  try {
    await navigator.clipboard.writeText(commands.textContent.trim());
    status.textContent = 'Copied both commands. Paste them into Terminal to install.';
  } catch {
    const range = document.createRange();
    range.selectNodeContents(commands);
    const selection = window.getSelection();
    selection.removeAllRanges();
    selection.addRange(range);
    status.textContent = 'Clipboard access is unavailable. The commands are selected; copy them manually.';
  }
});
