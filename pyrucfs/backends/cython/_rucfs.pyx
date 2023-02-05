# cython: language_level=3
# cython: cdivision=True
cimport cython
from cpython.mem cimport PyMem_Free, PyMem_Malloc
from libc.stdint cimport uint8_t, uint32_t

from pyrucfs.backends.cython.rucfs cimport (rucfs_ctx_t, rucfs_enumerate_path, ok,arguments,data_broken,unsupported,notfound,out_of_memory,
                                            rucfs_errcode_t, rucfs_exist,
                                            rucfs_fclose, rucfs_file_t,
                                            rucfs_fopen, rucfs_inode_directory,
                                            rucfs_inode_directory_t,
                                            rucfs_inode_file, rucfs_inode_name,
                                            rucfs_inode_symlink,
                                            rucfs_inode_symlink_t,
                                            rucfs_inode_t, rucfs_inode_type_t,
                                            rucfs_load, rucfs_normalize_path,
                                            rucfs_ok, rucfs_open_directory,
                                            rucfs_open_symlink,
                                            rucfs_path_enum_t, rucfs_path_to,
                                            rucfs_superblock_t)

INODE_DIRECTORY =  rucfs_inode_directory
INODE_FILE = rucfs_inode_file
INODE_SYMLINK = rucfs_inode_symlink

cdef inline str path_to_str(rucfs_path_enum_t* p):
    """
    directory or file or symlink
    """
    if p.type == rucfs_inode_directory:
        return "directory"
    elif p.type == rucfs_inode_file:
        return "file"
    elif  p.type == rucfs_inode_symlink:
        return "symlink"
    else:
        return "unknown"

cdef inline str check_err(rucfs_errcode_t  err):
    if err == ok:
        return "ok"
    elif err == arguments:
        return "arguments"
    elif err == data_broken:
        return "data_broken"
    elif err == unsupported:
        return "unsupported"
    elif err == notfound:
        return "notfound"
    elif err == out_of_memory:
        return "out_of_memory"

# @cython.internal  # uncomment this to
@cython.final
@cython.freelist(8)
@cython.no_gc
cdef class SuperBlock:
    """
    internal use
    """
    cdef rucfs_superblock_t * _block

    def __cinit__(self):
        self._block = <rucfs_superblock_t *> PyMem_Malloc(sizeof(rucfs_superblock_t))
        if not self._block:
            raise MemoryError

    def __dealloc__(self):
        if self._block:
            PyMem_Free(self._block)
            self._block = NULL

@cython.final
@cython.freelist(8)
@cython.no_gc
cdef class File:
    cdef:
        Py_ssize_t view_count
        Py_ssize_t shape[1]
        Py_ssize_t strides[1]
        rucfs_file_t* file

    @staticmethod
    cdef inline File from_ptr(rucfs_file_t* file):
        cdef File self = File.__new__(File)
        self.file = file
        self.view_count = 0
        self.strides[0] = 1
        return self

    @property
    def name(self):
        return <bytes>self.file.name

    cpdef inline close(self):
        cdef rucfs_errcode_t code = rucfs_fclose(self.file)
        if not rucfs_ok(code):
            raise IOError(check_err(code))

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        self.close()

    def __len__(self):
        return self.file.length

    # buffer protocol
    def __getbuffer__(self, Py_buffer * buffer, int flags):
        self.view_count += 1
        self.shape[0] = <Py_ssize_t> self.file.length
        cdef size_t itemsize = sizeof(uint8_t)
        buffer.buf = self.file.data
        buffer.obj = self
        buffer.len = self.shape[0] * itemsize
        buffer.readonly = 0
        buffer.itemsize = <Py_ssize_t> itemsize
        buffer.format = "B"
        buffer.ndim = 1
        buffer.shape = self.shape
        buffer.strides = self.strides
        buffer.suboffsets = NULL

    def __releasebuffer__(self, Py_buffer * buffer):
        self.view_count -= 1

@cython.final
@cython.freelist(8)
@cython.no_gc
cdef class Path:
    cdef rucfs_path_enum_t* path

    def __cinit__(self):
        self.path = <rucfs_path_enum_t *> PyMem_Malloc(sizeof(rucfs_path_enum_t))
        if not self.path:
            raise MemoryError

    def __dealloc__(self):
        if self.path:
            PyMem_Free(self.path)


    @staticmethod
    cdef inline Path from_ptr(rucfs_path_enum_t* path):
        cdef Path self = Path.__new__(Path)
        self.path[0] = path[0] # perform a deepcopy
        return self

    @property
    def name(self):
        return <bytes> self.path.name

    @property
    def type(self):
        """
        directory or file or symlink
        """
        return self.path.type

    def __str__(self):
        return f"Path: name = {self.name}, type = {path_to_str(self.path)}"

    __repr__ = __str__

@cython.final
@cython.freelist(8)
@cython.no_gc
cdef class Inode:
    cdef:
        rucfs_inode_t *node
        int own
    def __cinit__(self, rucfs_inode_type_t type_= rucfs_inode_directory, uint32_t name_offset = 0, bint own = True):
        if own:
            self.node = <rucfs_inode_t *> PyMem_Malloc(sizeof(rucfs_inode_t))
            if not self.node:
                raise MemoryError
            self.node.type = type_
            self.node.name_offset = name_offset
            self.own = 1
        else:
            self.own = 0

    def __dealloc__(self):
        if self.own and self.node:
            PyMem_Free(self.node)

    @staticmethod
    cdef inline Inode from_ptr(rucfs_inode_t *node):
        cdef Inode self = Inode.__new__(Inode, own = 0)
        self.node = node
        return self

    @property
    def type(self):
        """
        directory or file or symlink
        """
        return self.node.type

    @property
    def name_offset(self):
        return self.node.name_offset


@cython.final
@cython.freelist(8)
@cython.no_gc
cdef class Directory:
    cdef:
        rucfs_inode_directory_t* d
        int own

    def __cinit__(self, rucfs_inode_type_t type_= rucfs_inode_directory, uint32_t name_offset = 0, uint32_t item_count = 0, uint32_t ref_inode_offset = 0, bint own = True):
        if own:
            self.d = <rucfs_inode_directory_t *> PyMem_Malloc(sizeof(rucfs_inode_directory_t))
            if not self.d:
                raise MemoryError
            (<rucfs_inode_t *> self.d).type = type_
            (<rucfs_inode_t *> self.d).name_offset = name_offset
            self.d.item_count = item_count
            self.d.ref_inode_offset = ref_inode_offset
            self.own = 1
        else:
            self.own = 0

    def __dealloc__(self):
        if self.own and self.d:
            PyMem_Free(self.d)

    @staticmethod
    cdef inline Directory from_ptr(rucfs_inode_directory_t* d):
        cdef Directory self = Directory.__new__(Directory, own = 0)
        self.d = d
        return self

    @property
    def common(self):
        return Inode.from_ptr(&self.d.common)

    @property
    def item_count(self):
        return self.d.item_count

    @property
    def ref_inode_offset(self):
        return self.d.ref_inode_offset

@cython.final
@cython.freelist(8)
@cython.no_gc
cdef class Symlink:
    cdef:
        rucfs_inode_symlink_t* _link
        int own   # own this ptr (not from_ptr)

    def __cinit__(self, rucfs_inode_type_t type_ = rucfs_inode_directory, uint32_t name_offset = 0, uint32_t ref_inode_offset = 0, bint own = True):
        if own:   # user created struct
            self._link = <rucfs_inode_symlink_t *> PyMem_Malloc(sizeof(rucfs_inode_symlink_t))
            if not self._link:
                raise MemoryError
            (<rucfs_inode_t*>self._link).type = type_
            (<rucfs_inode_t *> self._link).name_offset = name_offset
            self._link.ref_inode_offset = ref_inode_offset
            self.own = 1
        else:  # from_ptr called
            self.own = 0


    def __dealloc__(self):
        if self.own and self._link:
            PyMem_Free(self._link)

    @staticmethod
    cdef inline Symlink from_ptr(rucfs_inode_symlink_t* link):
        cdef Symlink self =Symlink.__new__(Symlink, own = 0)
        self._link = link
        return self

    @property
    def common(self):
        return Inode.from_ptr(&self._link.common)

    @property
    def ref_inode_offset(self):
        return self._link.ref_inode_offset

@cython.final
@cython.freelist(8)
@cython.no_gc
cdef class Context:
    cdef:
        rucfs_ctx_t * _ctx
        const uint8_t[::1] data

    def __cinit__(self):
        self._ctx = <rucfs_ctx_t *> PyMem_Malloc(sizeof(rucfs_ctx_t))
        if not self._ctx:
            raise MemoryError

    def __dealloc__(self):
        if self._ctx:
            PyMem_Free(self._ctx)
            self._ctx = NULL

    cpdef File fopen(self, const uint8_t[::1] path):
        cdef rucfs_file_t* file
        cdef rucfs_errcode_t code = ok
        with nogil:
            code = rucfs_fopen(self._ctx, <const char *>&path[0], &file)
        if not rucfs_ok(code):
            raise IOError(check_err(code))
        return File.from_ptr(file)

    cpdef inline Inode open_symlink(self, Symlink link):
        cdef rucfs_inode_t * node
        with nogil:
            node = rucfs_open_symlink(self._ctx, link._link)
        return Inode.from_ptr(node)

    cpdef inline Inode open_directory(self, Directory d):
        cdef rucfs_inode_t * node
        with nogil:
            node = rucfs_open_directory(self._ctx, d.d)
        return Inode.from_ptr(node)

    cpdef inline Inode path_to(self, const uint8_t[::1] path):
        cdef:
            rucfs_inode_t* node
            rucfs_errcode_t code = ok
        with nogil:
            code = rucfs_path_to(self._ctx, <const char *> &path[0], &node)
        if not rucfs_ok(code):
            raise IOError(check_err(code))
        return Inode.from_ptr(node)

    cpdef inline bint exist(self, const uint8_t[::1] path) except *:
        cdef:
            rucfs_errcode_t err = ok
            bint code = False
        with nogil:
            code = rucfs_exist(self._ctx, <const char *> &path[0], &err)
        if not rucfs_ok(err):
            raise IOError(check_err(err))
        return code

    def __contains__(self, item):
        return self.exist(item)

    cpdef bytes inode_name(self,  Inode node):
        return  <bytes>rucfs_inode_name(self._ctx, node.node)

    def enumerate_path(self, const uint8_t[::1] path):  # todo segfault
        """
        path like a/b/c
        :param path:
        :return:
        """
        cdef size_t size, i
        # count files
        cdef rucfs_path_enum_t* list_
        cdef rucfs_errcode_t code = ok
        with nogil:
            code = rucfs_enumerate_path(self._ctx, <const char *> &path[0], NULL, &size)
        if not rucfs_ok(code):
            raise IOError(check_err(code))

        list_ = <rucfs_path_enum_t*>PyMem_Malloc(sizeof(rucfs_path_enum_t) * size)
        if not list_:
            raise MemoryError
        try:
            with nogil:
                code = rucfs_enumerate_path(self._ctx, <const char *>&path[0], list_, &size)  # must from same thread
            if not rucfs_ok(code):
                raise IOError(check_err(code))
            for i in range(size):
                yield Path.from_ptr( &list_[i])
        finally:
            PyMem_Free(list_)

    @staticmethod
    def load(const uint8_t[::1] data):
        """
        todo! keep a refcount to data! should we do that?
        :param data:
        :return:
        """
        cdef Context self = Context()
        self.data = data
        cdef rucfs_errcode_t code = ok
        with nogil:
            code = rucfs_load(<uint8_t*>&data[0],self._ctx)
        if not rucfs_ok(code):
            raise IOError(check_err(code))
        return self

    @property
    def rootdir(self):
        return Directory.from_ptr( self._ctx.rootdir)

cpdef inline size_t normalize_path(uint8_t[::1] buf, const uint8_t[::1] s, bint endslash) nogil:
    return rucfs_normalize_path(<char*>&buf[0],<const char*>&s[0], endslash)