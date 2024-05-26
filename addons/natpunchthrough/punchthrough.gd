extends Node

#region Custom Enums

# Enum to Track the stage of the Peer Connection
enum EPeerstage
{
	NoConfirm = 0,
	Greeted,
	Confirmed
}

#endregion

#region Signals

# emitted when punchthrough is completed
signal punchthrough_completed(_self_port, _host_address, _host_port)

# emmited when Session is Created. Only Emits on the host 
signal session_created()

# emitted when lobby get updated (Client joins or leaves 
signal lobby_updated(_client_names)

# emitted when process fails (both intentional and unintentional 
signal process_failed(_failure_message)

#endregion

#region Constants

# server Communication Consts

#Commands that can be sent to server
const REGISTER_SESSION = "rs:"
const DEREGISTER_SESSION = "ds:"
const REGISTER_CLIENT = "rc:"
const DEREGISTER_CLIENT = "dc:"
const EXCHANGE_PEERS = "ep:"
# Commands that are recieved from the Server 
const SERVER_OK = "ok:"
const SERVER_LOBBY = "lobby:"
const SERVER_INFO = "peers:"
const SERVER_CLOSE = "close:"
# Commnads sent between Peers
const PEER_GREET = "greet:"
const PEER_CONFIRM = "confirm:"
const HOST_START = "start:"
#endregion

#region NetworkPeers

# Packet Peer to Communicate with Intermediate Server
var server_udp = PacketPeerUDP.new()

# Packet Peer to Communicate with other peers
var peer_udp = PacketPeerUDP.new()

#endregion

#region Configuration

# The Public IP of the Intermediate Server
@export var ServerAddress = "3.15.157.211"

# The Port on which the Intermediate Server is Listening
@export var ServerPort = 5000

# Times the same message will be sent across before giving up 
@export var RepeatBuffer = 150

# The Range to check for Port Cascading in case greeting Fails 
@export var PortCascadeRange = 10

# Dev Variable to Check if Testing Locally. Will Overwrite the Peer IP with localhost 
@export var LocalTesting = true

#endregion

#region Flags 

# Caches if the Intermediate Server was found
var server_found = false

# caches whether peer information was recieved
var peer_info_recieved = false

# caches whether peer greets were recieved by all peers
var peer_greets_recieved = false

# caches whether peer confirmations were recieved by all peers
var peer_confirmations_recieved = false

# caches whether the local client is the host or not 
var is_host = false

#endregion

#region Local Cache
var ping_timer
var session_id
var client_name
var self_port
var peers = {}
var max_players = 10
var host_address
var host_port
#endregion

#region Counters

var greets = 0
var confirmations = 0
var ping_attempted = 0
var attempted_ports = 0
#endregion

#region Server Functions

# register the session
func _register_session():
	print ("Registering Session")
	var buffer = PackedByteArray()
	buffer.append_array((REGISTER_SESSION + session_id + ":" + str(max_players)).to_utf8_buffer())
	server_udp.close()
	server_udp.set_dest_address(ServerAddress, ServerPort)
	server_udp.put_packet(buffer)

# deregister the session
func _deregister_session():
	var buffer = PackedByteArray()
	buffer.append_array((DEREGISTER_SESSION + session_id).to_utf8_buffer())
	server_udp.close()
	server_udp.set_dest_address(ServerAddress, ServerPort)
	server_udp.put_packet(buffer)

# register the client
func _register_client():
	await get_tree().create_timer(2.0).timeout
	var buffer = PackedByteArray()
	buffer.append_array((REGISTER_CLIENT + client_name + ":" + session_id + ":" + str(is_host)).to_utf8_buffer())
	server_udp.close()
	server_udp.set_dest_address(ServerAddress, ServerPort)
	server_udp.put_packet(buffer)

# deregister the client
func _deregister_client():
	var buffer = PackedByteArray()
	buffer.append_array((DEREGISTER_CLIENT + client_name + ":" + session_id).to_utf8_buffer())
	server_udp.close()
	server_udp.set_dest_address(ServerAddress, ServerPort)
	server_udp.put_packet(buffer)

# function called to start the game before the Lobby has reached Max Players
func _finalise_lobby():
	var buffer = PackedByteArray()
	buffer.append_array((EXCHANGE_PEERS + str(session_id)).to_utf8_buffer())
	server_udp.set_dest_address(ServerAddress, ServerPort)
	server_udp.put_packet(buffer)

# function that is called when recieving pings from the intermediate Server 
func _recieve_server_pings():
	var _array_bytes = server_udp.get_packet()
	var _packet_string = _array_bytes.get_string_from_ascii()
	var _messages = _packet_string.split(":")
	if _packet_string.begins_with(SERVER_LOBBY):
		emit_signal("lobby_updated", _messages[1].split("."))
	elif _packet_string.begins_with(SERVER_CLOSE):
		_punchthrough_failed("Server Closed")
	elif _packet_string.begins_with(SERVER_OK):
		self_port = int(_messages[1])
		print("Listening on port " + _messages[1])
		emit_signal("session_created")
		if is_host and not server_found:
			_register_client()
		server_found = true
	elif _packet_string.begins_with(SERVER_INFO):
		print("Recieving Lobby info")
		if not peer_info_recieved:
			server_udp.close()
			_packet_string = _packet_string.right(-6) #after 'peers:'
			print (_packet_string)
			if _packet_string.length() > 2:
				var _clientdata = _packet_string.split(",") #this is formatted client:ip:port,client2:ip:port
				for c in _clientdata:
					var m = c.split(":")
					peers[m[0]] = {"port":m[2], "address":("127.0.0.1" if LocalTesting else m[1]),"hosting":(m[3]=="True"),"name":m[0], "stage":EPeerstage.NoConfirm}
					print(peers)
				peer_info_recieved = true
				# begin Handshake process between Peers 
				_start_peer_connection()
				print(peers)
			else:
				#apparently no peers were sent, host probably began without others.
				_punchthrough_failed("No peers found.") #report to game to handle accordingly

#endregion

#region Peer Functions 

func _recieve_greet(_peer_name, _peer_port):
	print(peers)
	if not _peer_name in peers:
		peers[_peer_name].stage = EPeerstage.NoConfirm
	if peers[_peer_name].stage == EPeerstage.NoConfirm:
		peers[_peer_name].stage = EPeerstage.Greeted
	peers[_peer_name].port = _peer_port
	if peers[_peer_name].hosting:
		print(client_name + ": Setting Host Address")
		host_address = peers[_peer_name].address
		host_port = _peer_port

func _recieve_confirmation(_peer_name, _peer_port):
	if not _peer_name in peers:
		peers[_peer_name].stage = EPeerstage.NoConfirm
	peers[_peer_name].stage = EPeerstage.Confirmed

func _recieve_start(_peer_name, _peer_port):
	peers[_peer_name].stage = EPeerstage.Confirmed
	if peers[_peer_name].hosting:
		peer_udp.close()
		server_udp.close()
		emit_signal("punchthrough_completed", int(self_port), host_address, host_port)
		ping_timer.stop()
		set_process(false)

# function to start pinging peers once server exchanges data between peers
func _ping_peer():
	var all_info = true
	var all_confirm = true
	for _peer in peers.keys():
		if _peer == client_name:
			continue
		var _peer_data = peers[_peer]
		var _stage = _peer_data.stage
		if _stage < EPeerstage.Greeted : all_info = false
		if _stage < EPeerstage.Confirmed : all_confirm = false
		
		# if a greet hasn't been sent then send a greet
		if _stage == EPeerstage.NoConfirm:
			# if the number of pings attempted crosses the buffer and still not greeted
			# try cascading
			# else send a greet
			if ping_attempted >= RepeatBuffer:
				_port_cascade(_peer_data.address, int(_peer_data.port))
			else:
				print("sending Greet to " + str(_peer_data.name))
				peer_udp.set_dest_address(_peer_data.address, int(_peer_data.port))
				var _buffer = PackedByteArray()
				_buffer.append_array((PEER_GREET + client_name + ":" + str(self_port)).to_utf8_buffer())
				peer_udp.put_packet(_buffer)
		if _stage == EPeerstage.Greeted and peer_greets_recieved:
			print("Sending Confirmation to " + str(_peer_data.name))
			peer_udp.set_dest_address(_peer_data.address, int(_peer_data.port))
			var _buffer = PackedByteArray()
			_buffer.append_array((PEER_CONFIRM + client_name + ":" + str(self_port)).to_utf8_buffer())
			peer_udp.put_packet(_buffer)
		if _stage < EPeerstage.Confirmed and ping_attempted >= (RepeatBuffer * 2):
			_punchthrough_failed( " Punchthtough could not be completed consider port forwarding" )
	if all_info:
		print("All Greets Recieved on " + client_name)
		peer_greets_recieved = true
	if all_confirm:
		print("All Confirms Recieved on " + client_name)		
		peer_confirmations_recieved = true
		if is_host:
			for p in peers.keys():
				if p != client_name:
					var peer = peers[p]
					print("Sending Start to " + str(peers[p].name))
					peer_udp.set_dest_address(peer.address, int(peer.port))
					var buffer = PackedByteArray()
					buffer.append_array((HOST_START + client_name + ":" + str(self_port)).to_utf8_buffer())
					peer_udp.put_packet(buffer)
			peer_udp.close()
			server_udp.close()
			emit_signal("punchthrough_completed", int(self_port), host_address, host_port)
			ping_timer.stop()
			set_process(false)
	ping_attempted += 1

func _recieve_peer_pings():
	var _array_bytes = peer_udp.get_packet()
	var _packet_string = _array_bytes.get_string_from_ascii()
	var _message = _packet_string.split(":")
	if _packet_string.begins_with(PEER_GREET):
		print("recieved peer greet! from " + _message[1] + " on " + client_name)
		_recieve_greet(_message[1], int(_message[2]))
	elif _packet_string.begins_with(PEER_CONFIRM):
		print("recieved peer confirm! from " + _message[1] + " on " + client_name)
		_recieve_confirmation(_message[1], int(_message[2]))
	elif _packet_string.begins_with(HOST_START):
		print("recieved host start! from " + _message[1] + " on " + client_name)
		_recieve_start(_message[1], int(_message[2]))
	else:
		print("recieved unrecognized peer message!")

func _port_cascade(_address, _peer_port):
	print("Attempting Port Cascading on " + client_name)
	for i in range(int(_peer_port) - PortCascadeRange, int(_peer_port) + PortCascadeRange):
		peer_udp.set_dest_address(_address, i)
		var buffer = PackedByteArray()
		buffer.append_array((PEER_GREET + ":" + client_name + ":" + str(self_port) + ":" + str(i)).to_utf8_buffer())
		peer_udp.put_packet(buffer)
		attempted_ports += 1

# Sends Goodbye message to Server and OPens the Peer UDP Port to incoming messages
func _start_peer_connection():
	#Send Goodbye Message to intermediate server and Close Server UDP 
	server_udp.put_packet("goodbye".to_utf8_buffer())
	server_udp.close()
	# Refresh Peer UDP 
	if peer_udp.is_bound():
		peer_udp.close()
	var err = peer_udp.bind(self_port, "*")
	if err != OK:
		print(str(err) + ": Error listening on port " + str(self_port))
		return
	ping_timer.start()

#endregion

#region Util Functions

func _punchthrough_failed(_error_message):
	if is_host and server_udp.is_bound() and server_found:
		_deregister_session()
	else:
		_deregister_client()
	ping_timer.stop()
	server_udp.close()
	peer_udp.close()
	emit_signal("process_failed", _error_message)

func _reset_local_data():
	peers = {}
	
	server_found = false
	peer_info_recieved = false
	peer_greets_recieved = false
	peer_confirmations_recieved = false
	
	greets = 0
	confirmations = 0
	ping_attempted = 0


func Start_Punchthrough(_session_id, _is_host, _name):
	if server_udp.is_bound():
		server_udp.close()

	var err = server_udp.bind(ServerPort, "*")
	if err != OK:
		_punchthrough_failed("Error listening on port: " + str(ServerPort) + " to server: " + ServerAddress)
		return
	set_process(true)
	
	_reset_local_data()
	
	session_id = _session_id
	client_name = _name
	is_host = _is_host
	
	if is_host:
		_register_session()
	else:
		_register_client()
#endregion

#region Godot Overrides

func _exit_tree():
	if is_host:
		_deregister_session()
	else:
		_deregister_client()
	server_udp.close()

func _ready():
	ping_timer = Timer.new()
	get_tree().get_root().call_deferred("add_child", ping_timer)
	ping_timer.timeout.connect(_ping_peer)
	ping_timer.wait_time = 0.1

func _process(delta):
	if peer_udp.get_available_packet_count() > 0:
		_recieve_peer_pings()
	if server_udp.get_available_packet_count() > 0:
		_recieve_server_pings()
#endregion
