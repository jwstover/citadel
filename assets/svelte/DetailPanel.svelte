<script>
  let { node = null, onclose } = $props();

  const typeLabels = {
    start: 'Start',
    end: 'End',
    action: 'Action',
    decision: 'Decision',
  };

  const typeColors = {
    start: 'oklch(77% 0.152 181.912)',
    end: 'oklch(83.92% 0.0901 136.87)',
    action: 'oklch(80% 0 0)',
    decision: 'oklch(80.39% 0.1148 241.68)',
  };

  function handleBackdropClick(e) {
    if (e.target === e.currentTarget) {
      onclose();
    }
  }
</script>

{#if node}
  <!-- svelte-ignore a11y_click_events_have_key_events a11y_no_static_element_interactions -->
  <div class="panel-backdrop" onclick={handleBackdropClick}>
    <div class="detail-panel">
      <div class="panel-header">
        <span class="panel-title">Node Details</span>
        <button class="close-btn" onclick={onclose}>✕</button>
      </div>

      <div class="panel-body">
        <div class="field">
          <span class="field-label">Label</span>
          <span class="field-value">{node.data.label}</span>
        </div>

        <div class="field">
          <span class="field-label">Type</span>
          <span
            class="type-tag"
            style="color: {typeColors[node.data.nodeType]}; border-color: {typeColors[node.data.nodeType]}"
          >
            {typeLabels[node.data.nodeType] || node.data.nodeType}
          </span>
        </div>

        {#if node.data.description}
          <div class="field">
            <span class="field-label">Description</span>
            <span class="field-value desc">{node.data.description}</span>
          </div>
        {/if}

        {#if node.data.status}
          <div class="field">
            <span class="field-label">Status</span>
            <span class="status-indicator" class:running={node.data.status === 'running'}>
              {#if node.data.status === 'running'}
                <span class="pulse-dot"></span>
              {/if}
              {node.data.status}
            </span>
          </div>
        {/if}

        <div class="field">
          <span class="field-label">ID</span>
          <span class="field-value mono">{node.id}</span>
        </div>
      </div>
    </div>
  </div>
{/if}

<style>
  .panel-backdrop {
    position: absolute;
    inset: 0;
    z-index: 10;
  }

  .detail-panel {
    position: absolute;
    top: 12px;
    right: 12px;
    width: 280px;
    background: oklch(12% 0 150);
    border: 1px solid oklch(25% 0 0);
    border-radius: 6px;
    box-shadow: 0 8px 32px rgba(0, 0, 0, 0.5);
    font-family: system-ui, -apple-system, sans-serif;
    color: oklch(93% 0.005 50);
    overflow: hidden;
  }

  .panel-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 10px 14px;
    border-bottom: 1px solid oklch(20% 0 150);
    background: oklch(10% 0 150);
  }

  .panel-title {
    font-size: 12px;
    font-weight: 600;
    text-transform: uppercase;
    letter-spacing: 0.05em;
    opacity: 0.6;
  }

  .close-btn {
    background: none;
    border: none;
    color: oklch(60% 0 0);
    cursor: pointer;
    font-size: 14px;
    padding: 2px 6px;
    border-radius: 4px;
    line-height: 1;
    transition: color 0.15s ease, background 0.15s ease;
  }

  .close-btn:hover {
    color: oklch(93% 0.005 50);
    background: oklch(20% 0 150);
  }

  .panel-body {
    padding: 12px 14px;
    display: flex;
    flex-direction: column;
    gap: 12px;
  }

  .field {
    display: flex;
    flex-direction: column;
    gap: 3px;
  }

  .field-label {
    font-size: 10px;
    font-weight: 600;
    text-transform: uppercase;
    letter-spacing: 0.05em;
    opacity: 0.45;
  }

  .field-value {
    font-size: 13px;
    line-height: 1.4;
  }

  .field-value.desc {
    opacity: 0.75;
  }

  .field-value.mono {
    font-family: 'SF Mono', 'Fira Code', monospace;
    font-size: 11px;
    opacity: 0.5;
  }

  .type-tag {
    display: inline-flex;
    align-self: flex-start;
    font-size: 11px;
    font-weight: 500;
    padding: 2px 8px;
    border: 1px solid;
    border-radius: 4px;
    background: oklch(15% 0 150);
  }

  .status-indicator {
    font-size: 12px;
    font-weight: 500;
    display: inline-flex;
    align-items: center;
    gap: 6px;
    text-transform: capitalize;
  }

  .status-indicator.running {
    color: oklch(77% 0.152 181.912);
  }

  @keyframes dot-pulse {
    0%, 100% { opacity: 0.4; }
    50% { opacity: 1; }
  }

  .pulse-dot {
    width: 6px;
    height: 6px;
    border-radius: 50%;
    background: oklch(77% 0.152 181.912);
    animation: dot-pulse 1.5s ease-in-out infinite;
  }
</style>
