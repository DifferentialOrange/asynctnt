local uuid = require 'uuid'

-- Based on tarantool/vshard version.lua
-- https://github.com/tarantool/vshard/blob/ce4c0a00227710be34fb361a932ba89f79814e0f/vshard/version.lua

--
-- Semver parser adopted to Tarantool's versions.
-- Almost everything is the same as in https://semver.org.
--
-- Tarantool's version has format:
--
--     x.x.x-typen-commit-ghash
--
-- * x.x.x - major, middle, minor release numbers;
-- * typen - release type and its optional number: alpha1, beta5, rc10.
--   Optional;
-- * commit - commit count since the latest release. Optional;
-- * ghash - latest commit hash in format g<hash>. Optional.
--
-- Differences with the semver docs:
--
-- * No support for nested releases like x.x.x-alpha.beta. Only x.x.x-alpha.
-- * Release number is written right after its type. Not 'alpha.1' but 'alpha1'.
--

local release_type_weight = {
    -- This release type is an invention of tarantool, is not documented in
    -- semver.
    entrypoint = 10,
    alpha = 20,
    beta = 30,
    rc = 40,
}

local function release_type_cmp(t1, t2)
    t1 = release_type_weight[t1]
    t2 = release_type_weight[t2]
    -- 'No release type' means the greatest.
    if not t1 then
        if not t2 then
            return 0
        end
        return 1
    end
    if not t2 then
        return -1
    end
    return t1 - t2
end

local function version_cmp(ver1, ver2)
    if ver1.id_major ~= ver2.id_major then
        return ver1.id_major - ver2.id_major
    end
    if ver1.id_middle ~= ver2.id_middle then
        return ver1.id_middle - ver2.id_middle
    end
    if ver1.id_minor ~= ver2.id_minor then
        return ver1.id_minor - ver2.id_minor
    end
    if ver1.rel_type ~= ver2.rel_type then
        return release_type_cmp(ver1.rel_type, ver2.rel_type)
    end
    if ver1.rel_num ~= ver2.rel_num then
        return ver1.rel_num - ver2.rel_num
    end
    if ver1.id_commit ~= ver2.id_commit then
        return ver1.id_commit - ver2.id_commit
    end
    return 0
end

local version_mt = {
    __eq = function(l, r)
        return version_cmp(l, r) == 0
    end,
    __lt = function(l, r)
        return version_cmp(l, r) < 0
    end,
    __le = function(l, r)
        return version_cmp(l, r) <= 0
    end,
}

local function version_new(id_major, id_middle, id_minor, rel_type, rel_num,
                           id_commit)
    -- There is no any proper validation - the API is not public.
    assert(id_major and id_middle and id_minor)
    return setmetatable({
        id_major = id_major,
        id_middle = id_middle,
        id_minor = id_minor,
        rel_type = rel_type,
        rel_num = rel_num,
        id_commit = id_commit,
    }, version_mt)
end

local function version_parse(version_str)
    --  x.x.x-name<num>-<num>-g<commit>
    -- \____/\___/\___/\_____/
    --   P1   P2   P3    P4
    local id_major, id_middle, id_minor
    local rel_type
    local rel_num = 0
    local id_commit = 0
    local pos

    -- Part 1 - version ID triplet.
    id_major, id_middle, id_minor = version_str:match('^(%d+)%.(%d+)%.(%d+)')
    if not id_major or not id_middle or not id_minor then
        error(('Could not parse version: %s'):format(version_str))
    end
    id_major = tonumber(id_major)
    id_middle = tonumber(id_middle)
    id_minor = tonumber(id_minor)

    -- Cut to 'name<num>-<num>-g<commit>'.
    pos = version_str:find('-')
    if not pos then
        goto finish
    end
    version_str = version_str:sub(pos + 1)

    -- Part 2 and 3 - release name, might be absent.
    rel_type, rel_num = version_str:match('^(%a+)(%d+)')
    if not rel_type then
        rel_type = version_str:match('^(%a+)')
        rel_num = 0
    else
        rel_num = tonumber(rel_num)
    end

    -- Cut to '<num>-g<commit>'.
    if rel_type then
        pos = version_str:find('-')
        if not pos then
            goto finish
        end
        version_str = version_str:sub(pos + 1)
    end

    -- Part 4 - commit count since latest release, might be absent.
    id_commit = version_str:match('^(%d+)')
    if not id_commit then
        id_commit = 0
    else
        id_commit = tonumber(id_commit)
    end

::finish::
    return version_new(id_major, id_middle, id_minor, rel_type, rel_num,
                       id_commit)
end

-- Naive implementation borrowed from luafun, covers all cases here.
local function is_array(tab)
    if type(tab) == 'table' then
        return #tab > 0
    end

    return false
end

local function check_version(expected, version)
    -- Backward compatibility.
    if is_array(expected) then
        local major, minor, patch, commit = unpack(expected)

        expected = version_new(major, minor, patch or 0, nil, nil, commit)
    end

    version = version or rawget(_G, '_TARANTOOL')
    if type(version) == 'string' then
        version = version_parse(version)
    end

    return expected < version
end

local function bootstrap()
    local b = {
        tarantool_ver = box.info.version,
        has_new_types = false,
        types = {}
    }

    function b:check_version(expected)
        return check_version(expected, self.tarantool_ver)
    end

    if b:check_version({1, 7, 1, 245}) then
        b.has_new_types = true
        b.types.string = 'string'
        b.types.unsigned = 'unsigned'
        b.types.integer = 'integer'
    else
        b.types.string = 'str'
        b.types.unsigned = 'num'
        b.types.integer = 'int'
    end
    b.types.decimal = 'decimal'
    b.types.uuid = 'uuid'
    b.types.datetime = 'datetime'
    b.types.number = 'number'
    b.types.array = 'array'
    b.types.scalar = 'scalar'
    b.types.any = '*'
    return b
end

_G.B = bootstrap()

function change_format()
    box.space.tester:format({
        {type=B.types.unsigned, name='f1'},
        {type=B.types.string, name='f2'},
        {type=B.types.unsigned, name='f3'},
        {type=B.types.unsigned, name='f4'},
        {type=B.types.any, name='f5'},
        {type=B.types.any, name='f6'},
    })
end

box.schema.func.create('change_format', {setuid=true})


box.once('v1', function()
    box.schema.user.create('t1', {password = 't1'})

    if B:check_version({2, 0}) then
        box.schema.user.grant('t1', 'read,write,execute,create,drop,alter', 'universe')
        box.schema.user.grant('guest', 'read,write,execute,create,drop,alter', 'universe')
    else
        box.schema.user.grant('t1', 'read,write,execute', 'universe')
    end

    local s = box.schema.create_space('tester')
    s:format({
        {type=B.types.unsigned, name='f1'},
        {type=B.types.string, name='f2'},
        {type=B.types.unsigned, name='f3'},
        {type=B.types.unsigned, name='f4'},
        {type=B.types.any, name='f5'},
    })
    s:create_index('primary')
    s:create_index('txt', {unique = false, parts = {2, B.types.string}})

    s = box.schema.create_space('no_schema_space')
    s:create_index('primary')
    s:create_index('primary_hash',
                   {type = 'hash', parts = {1, B.types.unsigned}})
end)

if B:check_version({2, 0}) then
    box.once('v2', function()
        box.execute([[
            CREATE TABLE sql_space (
                id INT PRIMARY KEY,
                name TEXT COLLATE "unicode"
            )
        ]])
        box.execute([[
            CREATE TABLE sql_space_autoincrement (
                id INT PRIMARY KEY AUTOINCREMENT,
                name TEXT
            )
        ]])
        box.execute([[
            CREATE TABLE sql_space_autoincrement_multiple (
                id INT PRIMARY KEY AUTOINCREMENT,
                name TEXT
            )
        ]])
    end)

    box.once('v2.1', function()
        if B:check_version({2, 2}) then
            local s = box.schema.create_space('tester_ext_dec')
            s:format({
                {type=B.types.unsigned, name='f1'},
                {type=B.types.decimal, name='f2'},
            })
            s:create_index('primary')
        end

        if B:check_version({2, 4, 1}) then
            s = box.schema.create_space('tester_ext_uuid')
            s:format({
                {type=B.types.unsigned, name='f1'},
                {type=B.types.uuid, name='f2'},
            })
            s:create_index('primary')
        end

        if B:check_version({2, 10, 0}) then
            s = box.schema.create_space('tester_ext_datetime')
            s:format({
                {type=B.types.unsigned, name='id'},
                {type=B.types.datetime, name='dt'},
            })
            s:create_index('primary')
        end
    end)
end


function make_third_index(name)
    local i = box.space.tester:create_index(name, {unique = true, parts = {3, B.types.unsigned}})
    return {i.id}
end


local function _truncate(sp)
    if sp == nil then
        return
    end

    local keys = {}
    for _, el in sp:pairs() do
        table.insert(keys, el[1])
    end

    for _, k in ipairs(keys) do
        sp:delete({k})
    end
end


function truncate()
    _truncate(box.space.tester)
    _truncate(box.space.no_schema_space)

    if box.space.SQL_SPACE ~= nil then
        box.execute('DELETE FROM sql_space')
    end

    if box.space.SQL_SPACE_AUTOINCREMENT ~= nil then
        box.execute('DELETE FROM sql_space_autoincrement')
    end

    if box.space.SQL_SPACE_AUTOINCREMENT_MULTIPLE ~= nil then
        box.execute('DELETE FROM sql_space_autoincrement_multiple')
    end

    _truncate(box.space.tester_ext_dec)
    _truncate(box.space.tester_ext_uuid)
    _truncate(box.space.tester_ext_datetime)
end


_G.fiber = require('fiber')


function func_long(t)
    fiber.sleep(t)
    return 'ok'
end


function func_param(p)
    return {p}
end


function func_param_bare(p)
    return p
end


function func_hello_bare()
    return 'hello'
end


function func_hello()
    return {'hello'}
end

function func_load_bin_str()
    local bin_data = uuid.bin()
    return box.space.tester:insert({
        100, bin_data, 12, 15, 'hello'
    })
end

function raise()
    box.error{reason='my reason'}
end

function async_action()
    if box.session.push then
        for i=1,5 do
            box.session.push('hello_' .. tostring(i))
            require'fiber'.sleep(0.01)
        end
    end

    return 'ret'
end
