cdef class PrepareRequest(BaseRequest):
    cdef:
        str query
        uint64_t statement_id

    cdef inline WriteBuffer encode(self, bytes encoding)
    cdef int encode_request(self, WriteBuffer buffer) except -1
