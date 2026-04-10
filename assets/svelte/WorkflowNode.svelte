<script>
  import { Handle, Position } from '@xyflow/svelte';

  let { data } = $props();

  const showTarget = data.nodeType !== 'start';
  const showSource = data.nodeType !== 'end';
</script>

{#if showTarget}
  <Handle type="target" position={Position.Top} />
{/if}

<div class="workflow-node" data-type={data.nodeType}>
  <div class="node-label">{data.label}</div>
  {#if data.description}
    <div class="node-desc">{data.description}</div>
  {/if}
</div>

{#if showSource}
  <Handle type="source" position={Position.Bottom} />
{/if}

<style>
  .workflow-node {
    padding: 10px 16px;
    border-radius: 8px;
    min-width: 150px;
    text-align: center;
    font-family: system-ui, -apple-system, sans-serif;
    box-shadow: 0 1px 3px rgba(0, 0, 0, 0.12), 0 1px 2px rgba(0, 0, 0, 0.08);
  }

  .workflow-node[data-type='start'] {
    background: linear-gradient(135deg, #10b981, #059669);
    color: white;
    border: 2px solid #047857;
    border-radius: 9999px;
    padding: 12px 24px;
  }

  .workflow-node[data-type='end'] {
    background: linear-gradient(135deg, #10b981, #059669);
    color: white;
    border: 2px solid #047857;
    border-radius: 9999px;
    padding: 12px 24px;
  }

  .workflow-node[data-type='action'] {
    background: linear-gradient(135deg, #6366f1, #4f46e5);
    color: white;
    border: 2px solid #4338ca;
  }

  .workflow-node[data-type='decision'] {
    background: linear-gradient(135deg, #f59e0b, #d97706);
    color: white;
    border: 2px solid #b45309;
  }

  .node-label {
    font-weight: 600;
    font-size: 13px;
    line-height: 1.2;
  }

  .node-desc {
    font-size: 11px;
    opacity: 0.85;
    margin-top: 4px;
    line-height: 1.3;
  }
</style>
