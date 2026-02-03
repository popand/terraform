import { useState, useRef, useEffect, useCallback } from 'react'
import ReactMarkdown from 'react-markdown'
import mermaid from 'mermaid'

// Initialize mermaid with dark theme
mermaid.initialize({
  startOnLoad: false,
  theme: 'dark',
  themeVariables: {
    primaryColor: '#7c3aed',
    primaryTextColor: '#fff',
    primaryBorderColor: '#5b21b6',
    lineColor: '#6b7280',
    secondaryColor: '#1f2937',
    tertiaryColor: '#374151',
    background: '#111827',
    mainBkg: '#1f2937',
    nodeBorder: '#4b5563',
    clusterBkg: '#1f2937',
    clusterBorder: '#4b5563',
    titleColor: '#f3f4f6',
    edgeLabelBackground: '#374151'
  },
  flowchart: {
    htmlLabels: true,
    curve: 'basis'
  }
})

// Configuration - will be replaced by environment variables
const CONFIG = {
  apiEndpoint: import.meta.env.VITE_API_ENDPOINT || '',
  apiKey: import.meta.env.VITE_API_KEY || '',
  mockMode: import.meta.env.VITE_MOCK_MODE === 'true' || (!import.meta.env.VITE_API_ENDPOINT)
}

// Mock responses for demo/preview mode
const mockResponses = {
  "read": `I've analyzed the Terraform files in your repository. Here's what I found:

## Infrastructure Overview

| Resource Type | Count | Module |
|--------------|-------|--------|
| VPCs | 2 | vpc |
| FortiGate Firewalls | 2 | fortigate |
| Ubuntu VMs | 2 | ubuntu |
| S3 Buckets | 2 | bedrock-agent |
| Lambda Functions | 7 | bedrock-agent |

## Key Components

1. **VPC Module** - Creates VPCs with public/private subnets
2. **FortiGate Module** - Deploys FortiGate NGFW with IPSec VPN
3. **Ubuntu Module** - Workload VMs in private subnets
4. **Bedrock Agent Module** - AI agent with Lambda functions

The infrastructure creates a hub-and-spoke network connected via IPSec VPN tunnel.`,

  "fortigate": `## FortiGate Module Resources

The FortiGate module creates the following resources:

### EC2 Instance
- **Type:** FortiGate NGFW (PAYG)
- **Instance Type:** t3.small
- **AMI:** FortiGate 7.4.x from AWS Marketplace

### Network Interfaces
- **port1 (public):** Management and VPN termination
- **port2 (private):** LAN interface for internal traffic

### Security Groups
- **Public SG:** HTTPS (443), SSH (22), IKE (500), NAT-T (4500)
- **Private SG:** All traffic from private subnet

### Bootstrap Configuration
\`\`\`hcl
- IPSec Phase 1: AES256-SHA256, PSK auth
- IPSec Phase 2: AES256-SHA256
- Firewall policies: VPN inbound/outbound
- Static routes: Remote subnet via VPN
\`\`\``,

  "plan": `## Terraform Plan Results

Running \`terraform plan\`...

\`\`\`
Plan: 0 to add, 0 to change, 0 to destroy.
\`\`\`

**Status:** Infrastructure is up to date. No changes required.

### Current Resources
- 80 total resources managed
- Last applied: Just now
- State: Consistent`,

  "documentation": `## Documentation Generated

I've created comprehensive documentation for your infrastructure:

### Files Created
- \`docs/INFRASTRUCTURE.md\` - Architecture overview
- \`docs/VPN_CONFIG.md\` - VPN configuration details
- \`docs/RUNBOOK.md\` - Operations runbook

### Architecture Diagram
\`\`\`
VPC1 (10.0.0.0/16)          VPC2 (10.100.0.0/16)
┌─────────────────┐         ┌─────────────────┐
│  FortiGate-1    │◄═══════►│  FortiGate-2    │
│  3.19.233.255   │  IPSec  │  3.135.21.14    │
├─────────────────┤         ├─────────────────┤
│  Ubuntu-1       │         │  Ubuntu-2       │
│  10.0.1.10      │◄───────►│  10.100.1.10    │
└─────────────────┘         └─────────────────┘
\`\`\`

Documentation saved to S3 bucket.`,

  "tests": `## Infrastructure Test Results

Running connectivity tests...

| Test | Status | Details |
|------|--------|---------|
| FortiGate 1 HTTPS | ✅ PASS | https://3.19.233.255 |
| FortiGate 2 HTTPS | ✅ PASS | https://3.135.21.14 |
| VPN Tunnel Status | ✅ PASS | Selectors 1/1 UP |
| FG1 → Ubuntu2 | ✅ PASS | 0% loss, 0.5ms |
| FG2 → Ubuntu1 | ✅ PASS | 0% loss, 0.5ms |

**Summary:** All 5 tests passed!

VPN tunnel is healthy with bidirectional traffic flow.`,

  "default": `I understand you're asking about the infrastructure. Here are some things I can help with:

- **Analyze files** - "Read and analyze the Terraform files"
- **Explain modules** - "What does the FortiGate module create?"
- **Run operations** - "Run terraform plan"
- **Generate docs** - "Generate documentation"
- **Run tests** - "Run connectivity tests"

What would you like me to do?`
}

function getMockResponse(message) {
  const lower = message.toLowerCase()
  if (lower.includes('read') || lower.includes('analyze')) return mockResponses.read
  if (lower.includes('fortigate')) return mockResponses.fortigate
  if (lower.includes('plan')) return mockResponses.plan
  if (lower.includes('documentation') || lower.includes('generate doc')) return mockResponses.documentation
  if (lower.includes('test') || lower.includes('connectivity')) return mockResponses.tests
  return mockResponses.default
}

// Mermaid diagram component
function MermaidDiagram({ chart }) {
  const containerRef = useRef(null)
  const [svg, setSvg] = useState('')
  const [error, setError] = useState(null)

  useEffect(() => {
    const renderDiagram = async () => {
      if (!chart || !containerRef.current) return

      try {
        const id = `mermaid-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`
        const { svg } = await mermaid.render(id, chart)
        setSvg(svg)
        setError(null)
      } catch (err) {
        console.error('Mermaid error:', err)
        setError(err.message)
      }
    }

    renderDiagram()
  }, [chart])

  if (error) {
    return (
      <pre className="bg-dark-400 p-4 rounded-lg overflow-x-auto text-sm text-gray-300">
        <code>{chart}</code>
      </pre>
    )
  }

  return (
    <div
      ref={containerRef}
      className="mermaid-container bg-dark-400 p-4 rounded-lg overflow-x-auto"
      dangerouslySetInnerHTML={{ __html: svg }}
    />
  )
}

// Custom code block renderer for markdown
function CodeBlock({ node, inline, className, children, ...props }) {
  const match = /language-(\w+)/.exec(className || '')
  const language = match ? match[1] : ''

  if (!inline && language === 'mermaid') {
    return <MermaidDiagram chart={String(children).replace(/\n$/, '')} />
  }

  return (
    <code className={className} {...props}>
      {children}
    </code>
  )
}

function App() {
  const [messages, setMessages] = useState([
    {
      role: 'assistant',
      content: `Welcome to the **Terraform Infrastructure Agent**!

I can help you with:
- **Analyze** Terraform files and explain the infrastructure
- **Execute** Terraform operations (plan, apply, destroy)
- **Generate** documentation for your infrastructure
- **Run tests** to validate deployed resources
- **Modify** Terraform code based on your requests

What would you like to do?`
    }
  ])
  const [input, setInput] = useState('')
  const [isLoading, setIsLoading] = useState(false)
  const [sessionId] = useState(() => `session-${Date.now()}`)
  const [showConfig, setShowConfig] = useState(false)
  const [apiEndpoint, setApiEndpoint] = useState(CONFIG.apiEndpoint)
  const [apiKey, setApiKey] = useState(CONFIG.apiKey)
  const [mockMode, setMockMode] = useState(CONFIG.mockMode)
  const messagesEndRef = useRef(null)

  const scrollToBottom = () => {
    messagesEndRef.current?.scrollIntoView({ behavior: 'smooth' })
  }

  useEffect(() => {
    scrollToBottom()
  }, [messages])

  const sendMessage = async (e) => {
    e.preventDefault()
    if (!input.trim() || isLoading) return

    const userMessage = input.trim()
    setInput('')
    setMessages(prev => [...prev, { role: 'user', content: userMessage }])
    setIsLoading(true)

    // Mock mode for preview/demo
    if (mockMode || !apiEndpoint) {
      await new Promise(resolve => setTimeout(resolve, 1500)) // Simulate delay
      setMessages(prev => [...prev, {
        role: 'assistant',
        content: getMockResponse(userMessage)
      }])
      setIsLoading(false)
      return
    }

    try {
      const response = await fetch(apiEndpoint, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'x-api-key': apiKey
        },
        body: JSON.stringify({
          message: userMessage,
          sessionId: sessionId
        })
      })

      if (!response.ok) {
        throw new Error(`API error: ${response.status}`)
      }

      const data = await response.json()
      setMessages(prev => [...prev, {
        role: 'assistant',
        content: data.response || data.message || 'No response received'
      }])
    } catch (error) {
      console.error('Error:', error)
      setMessages(prev => [...prev, {
        role: 'assistant',
        content: `**Error:** ${error.message}\n\nPlease check your API configuration and try again.`
      }])
    } finally {
      setIsLoading(false)
    }
  }

  const saveConfig = () => {
    // Disable mock mode if API endpoint is provided
    if (apiEndpoint && apiEndpoint.trim()) {
      setMockMode(false)
    }
    setShowConfig(false)
  }

  const examplePrompts = [
    "Tell me about this infrastructure",
    "What does the FortiGate module do?",
    "Show me the deployed instances",
    "Generate an architecture diagram",
    "Run connectivity tests"
  ]

  return (
    <div className="min-h-screen bg-gradient-to-br from-dark-100 to-dark-200 flex flex-col">
      {/* Header */}
      <header className="border-b border-gray-700 px-6 py-4 flex items-center justify-between">
        <div className="flex items-center gap-3">
          <img src="/terraform-icon.svg" alt="Terraform" className="w-8 h-8" />
          <div>
            <h1 className="text-xl font-semibold bg-gradient-to-r from-primary to-secondary bg-clip-text text-transparent">
              Terraform Infrastructure Agent
            </h1>
            <p className="text-sm text-gray-400">
              Powered by Amazon Bedrock
              {mockMode && <span className="ml-2 px-2 py-0.5 bg-yellow-500/20 text-yellow-400 rounded text-xs">Demo Mode</span>}
            </p>
          </div>
        </div>
        <button
          onClick={() => setShowConfig(true)}
          className="px-4 py-2 text-sm bg-dark-300 border border-gray-600 rounded-lg hover:bg-dark-200 transition-colors"
        >
          Settings
        </button>
      </header>

      {/* Configuration Modal */}
      {showConfig && (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50">
          <div className="bg-dark-200 border border-gray-700 rounded-xl p-6 w-full max-w-md mx-4">
            <h2 className="text-xl font-semibold mb-4 text-primary">API Configuration</h2>
            <div className="space-y-4">
              <div>
                <label className="block text-sm text-gray-400 mb-2">API Endpoint</label>
                <input
                  type="text"
                  value={apiEndpoint}
                  onChange={(e) => setApiEndpoint(e.target.value)}
                  placeholder="https://xxx.execute-api.us-east-2.amazonaws.com/prod/chat"
                  className="w-full bg-dark-300 border border-gray-600 rounded-lg px-4 py-2 text-white focus:outline-none focus:border-primary"
                />
              </div>
              <div>
                <label className="block text-sm text-gray-400 mb-2">API Key</label>
                <input
                  type="password"
                  value={apiKey}
                  onChange={(e) => setApiKey(e.target.value)}
                  placeholder="Enter your API key"
                  className="w-full bg-dark-300 border border-gray-600 rounded-lg px-4 py-2 text-white focus:outline-none focus:border-primary"
                />
              </div>
              <div className="flex gap-3 mt-6">
                <button
                  onClick={saveConfig}
                  className="flex-1 bg-primary text-dark-400 font-semibold py-2 rounded-lg hover:bg-primary/90 transition-colors"
                >
                  Save
                </button>
                {CONFIG.apiEndpoint && (
                  <button
                    onClick={() => setShowConfig(false)}
                    className="flex-1 bg-dark-300 border border-gray-600 py-2 rounded-lg hover:bg-dark-100 transition-colors"
                  >
                    Cancel
                  </button>
                )}
              </div>
            </div>
          </div>
        </div>
      )}

      {/* Messages */}
      <div className="flex-1 overflow-y-auto px-4 py-6">
        <div className="max-w-4xl mx-auto space-y-6">
          {messages.map((message, index) => (
            <div
              key={index}
              className={`flex ${message.role === 'user' ? 'justify-end' : 'justify-start'}`}
            >
              <div
                className={`max-w-[80%] rounded-2xl px-5 py-4 ${
                  message.role === 'user'
                    ? 'bg-primary/20 border border-primary/30'
                    : 'bg-dark-300 border border-gray-700'
                }`}
              >
                {message.role === 'assistant' ? (
                  <div className="prose prose-invert max-w-none">
                    <ReactMarkdown components={{ code: CodeBlock }}>{message.content}</ReactMarkdown>
                  </div>
                ) : (
                  <p className="text-white">{message.content}</p>
                )}
              </div>
            </div>
          ))}

          {isLoading && (
            <div className="flex justify-start">
              <div className="bg-dark-300 border border-gray-700 rounded-2xl px-5 py-4">
                <div className="flex items-center gap-2">
                  <div className="flex gap-1">
                    <span className="w-2 h-2 bg-primary rounded-full animate-bounce" style={{ animationDelay: '0ms' }}></span>
                    <span className="w-2 h-2 bg-primary rounded-full animate-bounce" style={{ animationDelay: '150ms' }}></span>
                    <span className="w-2 h-2 bg-primary rounded-full animate-bounce" style={{ animationDelay: '300ms' }}></span>
                  </div>
                  <span className="text-gray-400 text-sm">Agent is thinking...</span>
                </div>
              </div>
            </div>
          )}

          <div ref={messagesEndRef} />
        </div>
      </div>

      {/* Example Prompts */}
      {messages.length <= 1 && (
        <div className="px-4 pb-4">
          <div className="max-w-4xl mx-auto">
            <p className="text-sm text-gray-400 mb-3">Try one of these:</p>
            <div className="flex flex-wrap gap-2">
              {examplePrompts.map((prompt, index) => (
                <button
                  key={index}
                  onClick={() => setInput(prompt)}
                  className="px-4 py-2 bg-dark-300 border border-gray-700 rounded-full text-sm hover:border-primary hover:text-primary transition-colors"
                >
                  {prompt}
                </button>
              ))}
            </div>
          </div>
        </div>
      )}

      {/* Input */}
      <div className="border-t border-gray-700 px-4 py-4">
        <form onSubmit={sendMessage} className="max-w-4xl mx-auto">
          <div className="flex gap-3">
            <input
              type="text"
              value={input}
              onChange={(e) => setInput(e.target.value)}
              placeholder="Ask about your Terraform infrastructure..."
              disabled={isLoading}
              className="flex-1 bg-dark-300 border border-gray-600 rounded-xl px-5 py-3 text-white placeholder-gray-500 focus:outline-none focus:border-primary transition-colors disabled:opacity-50"
            />
            <button
              type="submit"
              disabled={isLoading || !input.trim()}
              className="px-6 py-3 bg-gradient-to-r from-primary to-secondary text-white font-semibold rounded-xl hover:opacity-90 transition-opacity disabled:opacity-50 disabled:cursor-not-allowed"
            >
              Send
            </button>
          </div>
        </form>
      </div>
    </div>
  )
}

export default App
