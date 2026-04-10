const WORKFLOW_NODES = [
  {
    id: "start",
    type: "workflow",
    data: { label: "Start", nodeType: "start", description: "Workflow begins" },
  },
  {
    id: "plan",
    type: "workflow",
    data: {
      label: "Plan",
      nodeType: "action",
      description: "Define approach and goals",
    },
  },
  {
    id: "research",
    type: "workflow",
    data: {
      label: "Research",
      nodeType: "action",
      description: "Gather context and information",
    },
  },
  {
    id: "execute",
    type: "workflow",
    data: {
      label: "Execute",
      nodeType: "action",
      description: "Implement the solution",
    },
  },
  {
    id: "quality",
    type: "workflow",
    data: {
      label: "Quality Check",
      nodeType: "action",
      description: "Verify output quality",
    },
  },
  {
    id: "review",
    type: "workflow",
    data: {
      label: "Review",
      nodeType: "decision",
      description: "Evaluate results",
    },
  },
  {
    id: "complete",
    type: "workflow",
    data: {
      label: "Complete",
      nodeType: "end",
      description: "Workflow finished",
    },
  },
];

const WORKFLOW_EDGES = [
  { id: "start-plan", source: "start", target: "plan", type: "smoothstep" },
  {
    id: "plan-research",
    source: "plan",
    target: "research",
    type: "smoothstep",
  },
  {
    id: "research-execute",
    source: "research",
    target: "execute",
    type: "smoothstep",
  },
  {
    id: "execute-quality",
    source: "execute",
    target: "quality",
    type: "smoothstep",
  },
  {
    id: "quality-review",
    source: "quality",
    target: "review",
    type: "smoothstep",
  },
  {
    id: "review-complete",
    source: "review",
    target: "complete",
    type: "smoothstep",
    label: "Approved",
  },
  {
    id: "review-execute",
    source: "review",
    target: "execute",
    type: "smoothstep",
    label: "Needs changes",
    animated: true,
  },
];

function loadCSS() {
  if (!document.querySelector("[data-workflow-css]")) {
    const link = document.createElement("link");
    link.rel = "stylesheet";
    link.href = "/assets/js/svelte/index.css";
    link.setAttribute("data-workflow-css", "");
    document.head.appendChild(link);
  }
}

const WorkflowEditor = {
  async mounted() {
    loadCSS();

    const svelteBundle = "/assets/js/svelte/index.js";
    const { WorkflowGraph } = await import(svelteBundle);

    this._component = new WorkflowGraph({
      target: this.el,
      props: {
        initialNodes: WORKFLOW_NODES,
        initialEdges: WORKFLOW_EDGES,
      },
    });
  },

  destroyed() {
    if (this._component) {
      this._component.$destroy();
    }
  },
};

export default WorkflowEditor;
