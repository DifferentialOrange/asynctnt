cdef enum ProtocolState:
    PROTOCOL_IDLE = 0
    PROTOCOL_GREETING = 1
    PROTOCOL_NORMAL = 2


cdef enum ConnectionState:
    CONNECTION_BAD = 0
    CONNECTION_CONNECTED = 1
    CONNECTION_FULL = 2


cdef class CoreProtocol:
    cdef:
        object host
        object port

        str encoding

        ProtocolState state
        ConnectionState con_state
        dict reqs

        bytearray rbuf
        tuple version
        bytes salt

    cdef bint _is_connected(self)
    cdef bint _is_fully_connected(self)

    cdef void _write(self, buf)
    cdef void _on_data_received(self, data)
    cdef void _process__greeting(self)
    cdef void _on_greeting_received(self)
    cdef void _on_connection_made(self)
    cdef void _on_connection_lost(self, exc)