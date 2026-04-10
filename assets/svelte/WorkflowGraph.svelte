<script>
  import { SvelteFlow, Controls, Background } from '@xyflow/svelte';
  import dagre from '@dagrejs/dagre';
  import WorkflowNode from './WorkflowNode.svelte';
  import '@xyflow/svelte/dist/style.css';

  let { initialNodes = [], initialEdges = [] } = $props();

  const NODE_WIDTH = 200;
  const NODE_HEIGHT = 80;

  function getLayoutedElements(rawNodes, rawEdges) {
    const g = new dagre.graphlib.Graph();
    g.setDefaultEdgeLabel(() => ({}));
    g.setGraph({ rankdir: 'TB', nodesep: 60, ranksep: 100 });

    for (const node of rawNodes) {
      g.setNode(node.id, { width: NODE_WIDTH, height: NODE_HEIGHT });
    }

    for (const edge of rawEdges) {
      g.setEdge(edge.source, edge.target);
    }

    dagre.layout(g);

    const layoutedNodes = rawNodes.map((node) => {
      const pos = g.node(node.id);
      return {
        ...node,
        position: {
          x: pos.x - NODE_WIDTH / 2,
          y: pos.y - NODE_HEIGHT / 2,
        },
      };
    });

    return { nodes: layoutedNodes, edges: rawEdges };
  }

  const nodeTypes = { workflow: WorkflowNode };
  const layout = getLayoutedElements(initialNodes, initialEdges);
</script>

<div class="workflow-graph-container">
  <SvelteFlow
    nodes={layout.nodes}
    edges={layout.edges}
    {nodeTypes}
    fitView
    proOptions={{ hideAttribution: true }}
  >
    <Controls />
    <Background />
  </SvelteFlow>
</div>

<style>
  .workflow-graph-container {
    width: 100%;
    height: 100%;
  }
</style>
