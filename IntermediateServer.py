from twisted.internet.protocol import DatagramProtocol
from twisted.internet import reactor
from time import sleep

import sys

# utils

def address_to_string(address):
    ip, port = address
    return ':'.join([ip, str(port)])

#region ServerProtocol class 

class ServerProtocol(DatagramProtocol):
    def __init__(self) -> None:
        super().__init__()
        self.active_sessions = {}
        self.active_clients = {}

    def request_register_client(self, _name, _session_id, _ip, _port, _is_host) -> None:
        if _name in self.active_clients:
            print("Client %s is already registered for a sesion " % _name)
            return
        _client = Client(_name, _session_id, _ip, _port, _is_host)
        if self.active_sessions[_session_id].register_client(_client):
            self.active_clients[_name] = _client
    
    def request_deregister_client(self, _name) -> None:
        if not _name in self.active_clients:
            print("Trying to remove an Inactive Client")
            return
        if self.active_sessions[self.active_clients[_name].session_id].deregister_client(self.active_clients[_name]):
            del self.active_clients[_name]

    def request_resolved_client(self, _name) -> None:
        if not _name in self.active_clients:
            print("Trying to resolve an Inactive Client")
            return
        del self.active_clients[_name]

    def create_session(self, _session_id, _max_players) -> bool:
        if _session_id in self.active_sessions:
            print("Session already exists cannot create a new one")
            return False
        _session = Session(_session_id, _max_players, self)
        self.active_sessions[_session_id] = _session
        print(self.active_sessions)
        return True
    
    def remove_session(self, _session_id) -> bool:
        if not _session_id in self.active_sessions:
            return False
        _message = bytes('close:SessionClosed', "utf-8")
        for _client in self.active_sessions[_session_id].registered_clients:
            self.transport.write(_message, (_client.ip, _client.port))
            try:
                del self.active_clients[_client.name]
            except KeyError:
                pass
        del self.active_sessions[_session_id]

    def datagramReceived(self, datagram, addr) -> None:
        print(datagram)
        _data_string = datagram.decode("utf-8")
        _msg_type = _data_string[:2]
        print(_msg_type)
        _ip, _port = addr
        print(_ip)
        print(str(_port))
        _split = _data_string.split(":")
        if _msg_type == "rs":
            print("Session being Registered")
            _session_id = _split[1]
            _max_players = int(_split[2])
            if(self.create_session(_session_id, _max_players)):
                self.transport.write(bytes('ok:' + str(_port), "utf-8"), (_ip, _port))
        elif _msg_type == "ds":
            _session_id = _split[1]
            self.remove_session(_session_id)
        elif _msg_type == "rc":
            _name = _split[1]
            _session_id = _split[2]
            if _session_id in self.active_sessions:
                self.request_register_client(_name, _session_id, _ip, _port, _split[3] == "true")
                self.transport.write(bytes('ok:' + str(_port), "utf-8"), (_ip, _port))
        elif _msg_type == "dc":
            _name = _split[1]
            _session_id = _split[2]
            if _session_id in self.active_sessions:
                self.request_deregister_client(_name)
        elif _msg_type == "ep":
            _session_id = _split[1]
            if _session_id in self.active_sessions:
                self.active_sessions[_session_id].resolve_lobby()

#endregion

#region Session Class

class Session:
    def __init__(self, _session_id, _max_client, _server) -> None:
        self.session_id = _session_id
        self.max_client = _max_client
        self.server = _server
        self.registered_clients = []
    
    def register_client(self, _client) -> bool:
        # return if the Client already exists 
        if _client in self.registered_clients :
            print("Client %s already exists in session %s" % _client, self.session_id)
            return False
        # add the client to the registed list
        self.registered_clients.append(_client)
        self.updated_lobby()
        # if the max players have been reached resolve lobby and discard the Session
        if len(self.registered_clients) == int(self.max_client):
            sleep(2)
            print("max Clients Joined Starting Session ")
            self.resolve_lobby()
        return True

    def deregister_client(self, _client) -> bool:
        if not _client in self.registered_clients :
            print ("Client %s does not exist is in session %s" % _client.name, self.session_id)
            return False
        self.registered_clients.remove(_client)
        self.updated_lobby()
        return True

    def resolve_lobby(self) -> None:
        for _addressed_client in self.registered_clients:
            _address_list = []
            for _client in self.registered_clients:
                # add all the Client details except the one that is being sent the data
                if not _client.name == _addressed_client:
                    _address_list.append(_client.name + ":" + address_to_string((_client.ip, _client.port)) + ":" + str(_client.is_host))
            _address_string = ",".join(_address_list)
            _message =  bytes("peers:" + _address_string, "utf-8")
            self.server.transport.write(_message, (_addressed_client.ip, _addressed_client.port))
        print("Peer information has been sent to all registered Peers. Deleting session %s" % self.session_id)
        for _client in self.registered_clients:
            self.server.request_resolved_client(_client.name)
        self.server.remove_session(self.session_id)
    
    def updated_lobby(self) -> None:
        _lobby_clients = []
        for _client in self.registered_clients:
            _lobby_clients.append(_client.name)
        _message = bytes("lobby:" + ".".join(_lobby_clients), "utf-8")
        for _client in self.registered_clients:
            self.server.transport.write(_message, (_client.ip, _client.port))

#endregion

#region Client Class
class Client:
    def __init__(self, _name, _session_id, _ip, _port, _is_host) -> None:
        self.name = _name
        self.session_id = _session_id
        self.ip = _ip
        self.port = _port
        self.is_host = _is_host
        self.received_peer_info = False

    def received_information(self) -> None:
        self.received_peer_info = True

#endregion

if __name__ == '__main__':
	if len(sys.argv) < 2:
		print("Usage: IntermediateServer.py PORT")
		sys.exit(1)

	port = int(sys.argv[1])
	reactor.listenUDP(port, ServerProtocol())
	print('Listening on *:%d' % (port))
	reactor.run()
