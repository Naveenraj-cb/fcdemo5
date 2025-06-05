#!/usr/bin/env -S deno run --allow-net --allow-env --allow-read

/**
 * Deno HTTP Server for Firecracker VM Demo
 * This server runs inside each Firecracker VM and provides:
 * - Health check endpoint
 * - VM information endpoint  
 * - Inter-VM communication capabilities
 * - Load balancing simulation
 */

const VM_ID = Deno.env.get("VM_ID") || "unknown";
const PORT = parseInt(Deno.env.get("PORT") || "8000");
const HOST = "0.0.0.0";

// VM registry for inter-VM communication
const VM_REGISTRY = new Map<string, string>();

// Simple in-memory storage for demo
const storage = new Map<string, any>();

// Initialize VM registry with known VMs
function initVMRegistry() {
  const vmCount = parseInt(Deno.env.get("VM_COUNT") || "3");
  for (let i = 1; i <= vmCount; i++) {
    if (i.toString() !== VM_ID) {
      VM_REGISTRY.set(`vm-${i}`, `172.16.${i}.2`);
    }
  }
  console.log(`🔗 VM Registry initialized:`, Object.fromEntries(VM_REGISTRY));
}

// Health check endpoint
async function healthCheck(): Promise<Response> {
  const uptime = performance.now() / 1000;
  const memUsage = Deno.memoryUsage();
  
  const health = {
    status: "healthy",
    vm_id: VM_ID,
    uptime_seconds: Math.floor(uptime),
    memory_usage: {
      rss: Math.floor(memUsage.rss / 1024 / 1024), // MB
      heap_used: Math.floor(memUsage.heapUsed / 1024 / 1024), // MB
    },
    timestamp: new Date().toISOString(),
  };

  return new Response(JSON.stringify(health, null, 2), {
    headers: { "Content-Type": "application/json" },
  });
}

// VM information endpoint
async function vmInfo(): Promise<Response> {
  const info = {
    vm_id: VM_ID,
    hostname: Deno.hostname(),
    platform: Deno.build,
    deno_version: Deno.version,
    available_endpoints: [
      "/health",
      "/info", 
      "/storage",
      "/storage/{key}",
      "/ping/{vm_id}",
      "/broadcast",
      "/cluster-status"
    ],
    connected_vms: Array.from(VM_REGISTRY.keys()),
    storage_keys: Array.from(storage.keys()),
  };

  return new Response(JSON.stringify(info, null, 2), {
    headers: { "Content-Type": "application/json" },
  });
}

// Storage endpoints
async function handleStorage(request: Request, pathname: string): Promise<Response> {
  const url = new URL(request.url);
  const key = pathname.split("/storage/")[1];

  if (request.method === "GET") {
    if (!key) {
      // List all storage
      const allData = Object.fromEntries(storage);
      return new Response(JSON.stringify(allData, null, 2), {
        headers: { "Content-Type": "application/json" },
      });
    } else {
      // Get specific key
      const value = storage.get(key);
      if (value === undefined) {
        return new Response(JSON.stringify({ error: "Key not found" }), {
          status: 404,
          headers: { "Content-Type": "application/json" },
        });
      }
      return new Response(JSON.stringify({ key, value }), {
        headers: { "Content-Type": "application/json" },
      });
    }
  } else if (request.method === "POST" && key) {
    // Set key-value
    try {
      const body = await request.json();
      storage.set(key, body);
      return new Response(JSON.stringify({ 
        success: true, 
        key, 
        value: body,
        vm_id: VM_ID 
      }), {
        headers: { "Content-Type": "application/json" },
      });
    } catch (error) {
      return new Response(JSON.stringify({ error: "Invalid JSON" }), {
        status: 400,
        headers: { "Content-Type": "application/json" },
      });
    }
  } else if (request.method === "DELETE" && key) {
    // Delete key
    const existed = storage.delete(key);
    return new Response(JSON.stringify({ 
      success: existed, 
      key,
      vm_id: VM_ID 
    }), {
      headers: { "Content-Type": "application/json" },
    });
  }

  return new Response("Method not allowed", { status: 405 });
}

// Ping another VM
async function pingVM(targetVmId: string): Promise<Response> {
  const targetIP = VM_REGISTRY.get(targetVmId);
  
  if (!targetIP) {
    return new Response(JSON.stringify({ 
      error: `VM ${targetVmId} not found in registry`,
      available_vms: Array.from(VM_REGISTRY.keys())
    }), {
      status: 404,
      headers: { "Content-Type": "application/json" },
    });
  }

  try {
    const startTime = performance.now();
    const response = await fetch(`http://${targetIP}:8000/health`, {
      signal: AbortSignal.timeout(5000), // 5 second timeout
    });
    const endTime = performance.now();
    
    if (response.ok) {
      const healthData = await response.json();
      return new Response(JSON.stringify({
        success: true,
        source_vm: VM_ID,
        target_vm: targetVmId,
        target_ip: targetIP,
        response_time_ms: Math.floor(endTime - startTime),
        target_health: healthData,
      }, null, 2), {
        headers: { "Content-Type": "application/json" },
      });
    } else {
      throw new Error(`HTTP ${response.status}`);
    }
  } catch (error) {
    return new Response(JSON.stringify({
      success: false,
      source_vm: VM_ID,
      target_vm: targetVmId,
      target_ip: targetIP,
      error: error.message,
    }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }
}

// Broadcast message to all VMs
async function broadcast(request: Request): Promise<Response> {
  try {
    const message = await request.json();
    const results = [];

    for (const [vmId, ip] of VM_REGISTRY) {
      try {
        const response = await fetch(`http://${ip}:8000/storage/broadcast`, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            from: VM_ID,
            message,
            timestamp: new Date().toISOString(),
          }),
          signal: AbortSignal.timeout(3000),
        });

        results.push({
          vm_id: vmId,
          ip,
          success: response.ok,
          status: response.status,
        });
      } catch (error) {
        results.push({
          vm_id: vmId,
          ip,
          success: false,
          error: error.message,
        });
      }
    }

    return new Response(JSON.stringify({
      broadcast_from: VM_ID,
      message,
      results,
      total_targets: VM_REGISTRY.size,
      successful: results.filter(r => r.success).length,
    }, null, 2), {
      headers: { "Content-Type": "application/json" },
    });
  } catch (error) {
    return new Response(JSON.stringify({ error: "Invalid JSON" }), {
      status: 400,
      headers: { "Content-Type": "application/json" },
    });
  }
}

// Cluster status check
async function clusterStatus(): Promise<Response> {
  const results = [];
  
  for (const [vmId, ip] of VM_REGISTRY) {
    try {
      const startTime = performance.now();
      const response = await fetch(`http://${ip}:8000/health`, {
        signal: AbortSignal.timeout(2000),
      });
      const endTime = performance.now();
      
      if (response.ok) {
        const health = await response.json();
        results.push({
          vm_id: vmId,
          ip,
          status: "online",
          response_time_ms: Math.floor(endTime - startTime),
          uptime_seconds: health.uptime_seconds,
          memory_mb: health.memory_usage?.rss || 0,
        });
      } else {
        results.push({
          vm_id: vmId,
          ip,
          status: "error",
          error: `HTTP ${response.status}`,
        });
      }
    } catch (error) {
      results.push({
        vm_id: vmId,
        ip,
        status: "offline",
        error: error.message,
      });
    }
  }

  const onlineCount = results.filter(r => r.status === "online").length;
  
  return new Response(JSON.stringify({
    cluster_health: {
      total_vms: VM_REGISTRY.size + 1, // +1 for current VM
      online_vms: onlineCount + 1,     // +1 for current VM
      offline_vms: VM_REGISTRY.size - onlineCount,
      current_vm: VM_ID,
    },
    vm_status: results,
    checked_at: new Date().toISOString(),
  }, null, 2), {
    headers: { "Content-Type": "application/json" },
  });
}

// Main request handler
async function handler(request: Request): Promise<Response> {
  const url = new URL(request.url);
  const pathname = url.pathname;

  console.log(`${new Date().toISOString()} - ${request.method} ${pathname} from ${url.hostname}`);

  // CORS headers for development
  const corsHeaders = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "GET, POST, DELETE, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type",
  };

  if (request.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    let response: Response;

    if (pathname === "/" || pathname === "/health") {
      response = await healthCheck();
    } else if (pathname === "/info") {
      response = await vmInfo();
    } else if (pathname.startsWith("/storage")) {
      response = await handleStorage(request, pathname);
    } else if (pathname.startsWith("/ping/")) {
      const targetVm = pathname.split("/ping/")[1];
      response = await pingVM(targetVm);
    } else if (pathname === "/broadcast") {
      response = await broadcast(request);
    } else if (pathname === "/cluster-status") {
      response = await clusterStatus();
    } else {
      response = new Response(JSON.stringify({
        error: "Not found",
        available_endpoints: ["/health", "/info", "/storage", "/ping/{vm_id}", "/broadcast", "/cluster-status"]
      }), {
        status: 404,
        headers: { "Content-Type": "application/json" },
      });
    }

    // Add CORS headers to response
    Object.entries(corsHeaders).forEach(([key, value]) => {
      response.headers.set(key, value);
    });

    return response;
  } catch (error) {
    console.error("Handler error:", error);
    const errorResponse = new Response(JSON.stringify({
      error: "Internal server error",
      details: error.message,
      vm_id: VM_ID,
    }), {
      status: 500,
      headers: { "Content-Type": "application/json", ...corsHeaders },
    });

    return errorResponse;
  }
}

// Start the server
async function startServer() {
  initVMRegistry();
  
  console.log(`🚀 Starting Deno server on VM ${VM_ID}`);
  console.log(`📡 Listening on http://${HOST}:${PORT}`);
  console.log(`🔗 Connected to ${VM_REGISTRY.size} other VMs`);
  
  const server = Deno.serve({ 
    hostname: HOST, 
    port: PORT,
    onListen: ({ hostname, port }) => {
      console.log(`✅ Server running on http://${hostname}:${port}`);
      console.log(`🏷️  VM ID: ${VM_ID}`);
      console.log(`📊 Available endpoints:`);
      console.log(`   GET  /health          - Health check`);
      console.log(`   GET  /info            - VM information`);
      console.log(`   GET  /storage         - List all stored data`);
      console.log(`   POST /storage/{key}   - Store data`);
      console.log(`   GET  /storage/{key}   - Get data`);
      console.log(`   DEL  /storage/{key}   - Delete data`);
      console.log(`   GET  /ping/{vm_id}    - Ping another VM`);
      console.log(`   POST /broadcast       - Broadcast to all VMs`);
      console.log(`   GET  /cluster-status  - Check cluster health`);
    }
  }, handler);

  return server;
}

// Graceful shutdown
function setupGracefulShutdown(server: Deno.HttpServer) {
  const cleanup = () => {
    console.log("\n🛑 Shutting down server gracefully...");
    server.shutdown();
    Deno.exit(0);
  };

  Deno.addSignalListener("SIGINT", cleanup);
  Deno.addSignalListener("SIGTERM", cleanup);
}

// Main execution
if (import.meta.main) {
  const server = await startServer();
  setupGracefulShutdown(server);
}