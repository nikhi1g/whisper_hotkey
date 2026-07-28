# Security

Do not open a public issue for a vulnerability that could expose audio,
transcripts, clipboard contents, or local execution.

Report security issues privately through GitHub's **Security → Report a
vulnerability** flow. Include the affected version, reproduction steps, and
expected impact. Do not attach real private audio or transcripts.

The project has no cloud service or telemetry endpoint. Its security boundary is
the local macOS process, Accessibility/Input Monitoring permissions, temporary
audio directory, pasteboard transaction, helper process group, and downloaded
model integrity.
