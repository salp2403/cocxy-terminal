// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// RelayClientBootstrap.swift - Authenticated remote relay client command.

import Foundation

struct RelayClientBootstrap: Sendable {
    let channelID: UUID
    let remotePort: Int

    func shellCommand() -> String {
        let script = """
        import base64, getpass, hashlib, hmac, os, select, socket, struct, sys, time, uuid
        channel = uuid.UUID("\(channelID.uuidString)").bytes
        timestamp = int(time.time())
        nonce = os.urandom(\(RelayHandshake.nonceSize))
        payload = channel + struct.pack(">Q", timestamp) + nonce
        token_text = os.environ.get("COCXY_RELAY_TOKEN") or getpass.getpass("Relay token: ")
        secret = base64.b64decode(token_text)
        signature = hmac.new(secret, payload, hashlib.sha256).digest()
        relay = socket.create_connection(("127.0.0.1", \(remotePort)))
        relay.sendall(struct.pack(">I", len(payload)) + payload + signature)
        stdin = sys.stdin.buffer
        readers = [relay, stdin]
        while readers:
            ready, _, _ = select.select(readers, [], [])
            if relay in ready:
                data = relay.recv(65536)
                if not data:
                    readers.remove(relay)
                else:
                    sys.stdout.buffer.write(data)
                    sys.stdout.buffer.flush()
            if stdin in ready:
                data = os.read(sys.stdin.fileno(), 65536)
                if data:
                    try:
                        relay.sendall(data)
                    except (BrokenPipeError, OSError):
                        readers.remove(stdin)
                else:
                    try:
                        relay.shutdown(socket.SHUT_WR)
                    except OSError:
                        pass
                    readers.remove(stdin)
        relay.close()
        """
        let encodedScript = Data(script.utf8).base64EncodedString()
        return "python3 -c 'import base64;exec(base64.b64decode(\"\(encodedScript)\"))'"
    }
}
