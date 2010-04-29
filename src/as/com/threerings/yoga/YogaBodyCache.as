//
// $Id$
//
// Yoga library - classes for manipulating bodies
// Copyright (C) 2007-2010 Three Rings Design, Inc., All Rights Reserved
// http://code.google.com/p/ooo-yoga/
//
// This library is free software; you can redistribute it and/or modify it
// under the terms of the GNU Lesser General Public License as published
// by the Free Software Foundation; either version 2.1 of the License, or
// (at your option) any later version.
//
// This library is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
// Lesser General Public License for more details.
//
// You should have received a copy of the GNU Lesser General Public
// License along with this library; if not, write to the Free Software
// Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307 USA

package com.threerings.yoga {

import com.threerings.util.Comparators;
import com.threerings.util.Log;
import com.threerings.util.Map;
import com.threerings.util.Maps;

import flash.utils.getTimer;

/**
 * A simple LRU cache for YogaBody.
 */
public class YogaBodyCache
{
    /**
     * Creates a new cache.
     *
     * @param maxCacheSize the number of body types that the cache will store before pruning
     * the least-recently-used entries.
     *
     * @param defaultStateName the state that YogaBodys will be set to when they are retrieved
     * from the cache. Defaults to "Default" if unspecified.
     *
     * @param cacheTokenClazz the Class of the "cacheTokens" that will be used to cache and retrieve
     * YogaBodies. There must be a 1:1 relationship between each visually unique type of YogaBody,
     * and the body's associated cacheToken. Two YogaBodies that are identical should share the
     * same cacheToken. When a YogaBody is reskinned, its cacheToken should be updated accordingly.
     * Defaults to 'Object' if unspecified.
     */
    public function YogaBodyCache (maxCacheSize :int = 20, defaultStateName :String = "Default",
        cacheTokenClazz :Class = null)
    {
        _maxCacheSize = maxCacheSize;
        _defaultStateName = defaultStateName;
        _cacheTokenClazz = (cacheTokenClazz != null ? cacheTokenClazz : Object);
        initCacheMap();
    }

    /**
     * Shuts down all YogaBodies contained in the cache, and frees the cache's memory.
     */
    public function shutdown () :void
    {
        _caches.forEach(function (key :Object, cache :Cache) :void {
            cache.shutdown();
        });
        initCacheMap();
    }

    /**
     * Returns a YogaBody that was stored in the cache with the given cacheToken, or null
     * if body exists for that token.
     */
    public function getBody (cacheToken :Object) :YogaBody
    {
        var cache :Cache = getCache(cacheToken);
        if (cache.bodies.length > 0) {
            log.debug("cache HIT");
            var cachedBody :YogaBody = cache.bodies.pop();
            cachedBody.scaleX = cachedBody.scaleY = 1;
            cachedBody.x = cachedBody.y = 0;
            cachedBody.filters = [];
            cachedBody.setState(_defaultStateName, false);
            return cachedBody;
        }

        log.debug("cache MISS");
        return null;
    }

    /**
     * Stores a YogaBody in the cache.
     */
    public function cacheBody (body :YogaBody, cacheToken :Object) :void
    {
        var cache :Cache = getCache(cacheToken);
        cache.bodies.push(body);

        if (_maxCacheSize >= 0 && _caches.size() > _maxCacheSize) {
            log.debug("Pruning cache");
            // prune our cache when it gets too big
            var caches :Array = _caches.values().sort(
                function (a :Cache, b :Cache) :int {
                    return Comparators.compareInts(b.lastUsedTime, a.lastUsedTime);
                });
            initCacheMap();
            for (var ii :int = 0; ii < caches.length; ++ii) {
                var ac :Cache = caches[ii];
                if (ii < _maxCacheSize) {
                    _caches.put(ac.token, ac);
                } else {
                    ac.shutdown();
                }
            }
        }
    }

    protected function getCache (cacheToken :Object) :Cache
    {
        var cache :Cache = _caches.get(cacheToken);
        if (cache == null) {
            cache = new Cache(cacheToken);
            _caches.put(cacheToken, cache);
        }
        cache.lastUsedTime = flash.utils.getTimer();
        return cache;
    }

    protected function initCacheMap () :void
    {
        _caches = Maps.newMapOf(_cacheTokenClazz);
    }

    protected var _maxCacheSize :int;
    protected var _defaultStateName :String;
    protected var _cacheTokenClazz :Class;
    protected var _caches :Map; // Map<CacheToken, AvatarCache>

    protected static const log :Log = Log.getLog(YogaBodyCache);
}

}

import com.threerings.yoga.YogaBody;

class Cache
{
    public var token :Object;
    public var bodies :Array = []; // Array<YogaBody>
    public var lastUsedTime :int;

    public function Cache (token :Object)
    {
        this.token = token;
    }

    public function shutdown () :void
    {
        for each (var avatar :YogaBody in bodies) {
            avatar.shutdown();
        }
        bodies = null;
    }
}
