# Ek Blender örneği (paralel ajanlar): MCP eklentisini etkinleştirir, sunucuyu verilen portta başlatır.
#   KK_MCP_PORT=9877 Blender --python tools/argon/blender_mcp_port.py   (paralel_blender.sh çağırır)
import os
import sys

import addon_utils
import bpy

port = int(os.environ.get("KK_MCP_PORT", "9877"))


def log(*a):
    print(*a)
    sys.stdout.flush()


def baslat():
    try:
        if not addon_utils.check("blender_mcp")[1]:
            addon_utils.enable("blender_mcp", default_set=True, persistent=True)
        bpy.context.scene.blendermcp_port = port
        bpy.ops.blendermcp.start_server()
        log("MCP BASLADI", port)
        return None
    except Exception as e:
        log("MCP HATA", repr(e))
        return 2.0


bpy.app.timers.register(baslat, first_interval=3.0)
