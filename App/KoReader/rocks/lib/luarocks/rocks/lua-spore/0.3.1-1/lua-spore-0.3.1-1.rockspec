package = 'lua-Spore'
version = '0.3.1-1'
source = {
    url = 'http://sites.google.com/site/fperrad/lua-spore-0.3.1.tar.gz',
    md5 = '7c37d7838674062de516e838a20de6a6',
    dir = 'lua-Spore-0.3.1',
}
description = {
    summary = "a generic ReST client",
    detailed = [[
        lua-Spore is an implementation of SPORE (Specification to a POrtable Rest Environment),
        see http://github.com/SPORE/specifications.

        Some specifications of service are available at
        http://github.com/SPORE/api-description.
    ]],
    homepage = 'http://fperrad.github.com/lua-Spore',
    maintainer = 'Francois Perrad',
    license = 'MIT/X11'
}
dependencies = {
    'lua >= 5.1',
   -- 'luasocket >= 2.0.2',
--    'luasec >= 0.4',            -- libssl-dev
    'luajson >= 1.3',
--    'luaexpat >= 1.1.0',        -- libexpat1-dev
--    'lyaml >= 5',               -- libyaml-dev
--    'lualogging >= 1.1.4',
--    'luacrypto >= 0.2.0',
--    'lua-testmore >= 0.3.0',            -- test only
--    'lua-testlongstring >= 0.2.0',      -- test only
}
build = {
    type = 'builtin',
    modules = {
        ['Spore']                               = 'src/Spore.lua',
        ['Spore.Core']                          = 'src/Spore/Core.lua',
        ['Spore.GoogleDiscovery']               = 'src/Spore/GoogleDiscovery.lua',
        ['Spore.Middleware.Auth.AWS']           = 'src/Spore/Middleware/Auth/AWS.lua',
        ['Spore.Middleware.Auth.Basic']         = 'src/Spore/Middleware/Auth/Basic.lua',
        ['Spore.Middleware.Auth.Bearer']        = 'src/Spore/Middleware/Auth/Bearer.lua',
        ['Spore.Middleware.Auth.DataPublica']   = 'src/Spore/Middleware/Auth/DataPublica.lua',
        ['Spore.Middleware.Auth.Digest']        = 'src/Spore/Middleware/Auth/Digest.lua',
        ['Spore.Middleware.Auth.OAuth']         = 'src/Spore/Middleware/Auth/OAuth.lua',
        ['Spore.Middleware.Cache']              = 'src/Spore/Middleware/Cache.lua',
        ['Spore.Middleware.DoNotTrack']         = 'src/Spore/Middleware/DoNotTrack.lua',
        ['Spore.Middleware.Format.JSON']        = 'src/Spore/Middleware/Format/JSON.lua',
        ['Spore.Middleware.Format.XML']         = 'src/Spore/Middleware/Format/XML.lua',
        ['Spore.Middleware.Format.YAML']        = 'src/Spore/Middleware/Format/YAML.lua',
        ['Spore.Middleware.Logging']            = 'src/Spore/Middleware/Logging.lua',
        ['Spore.Middleware.Mock']               = 'src/Spore/Middleware/Mock.lua',
        ['Spore.Middleware.Parameter.Default']  = 'src/Spore/Middleware/Parameter/Default.lua',
        ['Spore.Middleware.Parameter.Force']    = 'src/Spore/Middleware/Parameter/Force.lua',
        ['Spore.Middleware.Proxy.Basic']        = 'src/Spore/Middleware/Proxy/Basic.lua',
        ['Spore.Middleware.Redirection']        = 'src/Spore/Middleware/Redirection.lua',
        ['Spore.Middleware.Runtime']            = 'src/Spore/Middleware/Runtime.lua',
        ['Spore.Middleware.UserAgent']          = 'src/Spore/Middleware/UserAgent.lua',
        ['Spore.Protocols']                     = 'src/Spore/Protocols.lua',
        ['Spore.Request']                       = 'src/Spore/Request.lua',
        ['Spore.WADL']                          = 'src/Spore/WADL.lua',
        ['Spore.XML']                           = 'src/Spore/XML.lua',
    },
    install = {
        bin = {
            'src/discovery2spore',
            'src/wadl2spore',
        }
    },
    copy_directories = { 'doc', 'test' },
}
