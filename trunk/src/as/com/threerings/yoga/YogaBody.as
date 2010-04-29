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

import com.threerings.display.DisplayUtil;
import com.threerings.util.ClassUtil;
import com.threerings.util.EventHandlerManager;
import com.threerings.util.Log;
import com.threerings.util.Map;
import com.threerings.util.Maps;
import com.threerings.util.Random;
import com.threerings.util.Util;

import flash.display.DisplayObject;
import flash.display.DisplayObjectContainer;
import flash.display.MovieClip;
import flash.display.Sprite;
import flash.events.Event;
import flash.geom.Point;

/**
 * This is the base for an avatar that can be configured/changed by the addition of external
 * MovieClips.
 */
public class YogaBody extends Sprite
{
    public function YogaBody ()
    {
        // update every frame
        _events.registerListener(this, Event.ENTER_FRAME, updateBody);
    }

    /**
     * Cleans up after our AvatarBody, unregistering listeners, etc.
     */
    public function shutdown () :void
    {
        _events.freeAllHandlers();
        _events = null;
        _movies = null;
    }

    /**
     * Adds a new movie to the AvatarBody. By default, the movie's name is determined
     * automatically by its Class name (though this won't work if the movie wasn't
     * "Exported for ActionScript" in the FAT).
     *
     * Movie names are of the form (state|action)_NAME(_N:W) or NAME_to_NAME.
     *
     * Movies can be "states" (which play until a new state is selected), "actions" (which play
     * once and then the Avatar reverts to its previous state movie), and "transitions" (which
     * play automatically to transition between two states, a state and an action, or an
     * action and a state.
     *
     * Valid name examples:
     * state_stand (a state named "hop")
     * action_punch (an action named "punch")
     * stand_to_punch (a transition that will play automatically when the "punch action is played
     *   while the "stand" state is active)
     *
     * states and actions can have multiple movies associated with them. The avatar will pick
     * one of these randomly when the state or action is played. You can assign weights to
     * alternate versions of state and action movies to determine the chance that they will
     * be played with the following naming convention:
     *
     * state_NAME_N:W (where N is any integer, and W is the integer weight). For example:
     *
     * state_walk_01:2
     * state_walk_02:1
     *
     * (The value of 'N' has no effect internally; it exists only to prevent name clashes)
     *
     * The first walk state will be played twice as frequently as the second.
     *
     * Movies default to a weight of 1.
     *
     * Movie names will be converted to lowercase automatically.
     */
    public function registerMovie (movie :MovieClip, movieName :String = null) :void
    {
        if (movieName == null) {
            // Determine the movie name from it's class name.
            movieName = ClassUtil.getClassName(movie);
        }
        movieName = movieName.toLowerCase();

        var bits :Array = movieName.split("_");
        if (bits.length < 2 || bits.length > 3) {
            log.warning("Invalid movie name", "movie", movieName);
            return;
        }

        var loc :Point = new Point(movie.x, movie.y);

        if (bits.length == 3 && String(bits[1]) == "to") { // NAME_to_NAME
            _movies.put(movieName, new MovieList(movieName, true, movie, loc));
            return;
        }

        // see if we have a weight specification.
        // "number" is not used for anything internally; it exists in the naming convention
        // to prevent name clashes.
        var weight :int = 1, number :int = 1;
        var wstr :String = String(bits[bits.length-1]);
        if (wstr.match("[0-9]+(\.[0-9]+)")) {
            var cidx :int = wstr.indexOf(".");
            if (cidx != -1) {
                number = int(wstr.substring(0, cidx));
                weight = int(wstr.substring(cidx+1));
            } else {
                number = int(wstr);
            }
            bits.pop();
        }

        var key :String;
        var type :String = String(bits[0]);
        var name :String = String(bits[1]);
        if (bits.length == 2 && (type == "action" || type == "state")) {
            key = type + "_" + name;
        } else {
            log.warning("Invalid movie name", "movie", movieName);
            return;
        }

        var list :MovieList = getMovie(key);
        if (list == null) {
            _movies.put(key.toLowerCase(), new MovieList(key, false, movie, loc, weight));
        } else {
            list.addMovie(movie, loc, weight);
        }
    }

    /**
     * Switches to a new state, using a transition animation if possible.
     */
    public function setState (state :String, transitionAllowed :Boolean = true) :void
    {
        state = state.toLowerCase();
        var stateScene :MovieList = getMovie("state_" + state);
        if (stateScene == null) {
            log.error("switchToState: missing state scene", "state", state);
            return; // ignore it
        }

        // transtion from our current state to the new state
        var queuedTransition :Boolean = transitionAllowed && queueTransitions(_state, state, true);
        // update our internal state variable
        _state = state;
        // queue our new state animation, transitioning to it immediately if we didn't queue
        // a transition
        queueMovie(stateScene, !queuedTransition);

        // If we're not attached, update now so the animation media is attached
        if (this.stage == null) {
            updateBody();
        }
    }

    /**
     * Triggers an action animation, using transition animations if possible.
     */
    public function triggerAction (action :String, transitionAllowed :Boolean = true) :void
    {
        action = action.toLowerCase();
        var actionScene :MovieList = getMovie("action_" + action);
        if (actionScene == null) {
            log.error("triggerAction: missing action scene", "action", action);
            return; // ignore it
        }

        // transition from our current state to the action
        var queuedTransition :Boolean = transitionAllowed && queueTransitions(_state, action, true);
        // play the action animation
        queueMovie(actionScene, !queuedTransition);
        // then transition back to our current state
        queueTransitions(action, _state, false);
        // and queue our current animation again
        queueMovie(getMovie("state_" + _state), false);

        // If we're not attached, update now so the animation media is attached
        if (this.stage == null) {
            updateBody();
        }
    }

    /**
     * Returns true if we're currently transitioning between states.
     */
    public function inTransition () :Boolean
    {
        return (_playing != null && _playing.isTransition);
    }

    /**
     * For each movie registered with the AvatarBody, replaces the children of that movie's
     * descendent, specified by 'path', with the DisplayObject created by the
     * specified createDisplayObject function. Ignores movies for which the descendent doesn't
     * exist.
     *
     * @param path the path used to find the nodes that will be reskinned.
     *
     * @param createDisplayObject a Function that generates a DisplayObject for each node that will
     * be reskinned. If null, the nodes' existing skins are removed, and no new skin is added.
     */
    public function setSkinAt (path :String, createDisplayObject :Function = null) :void
    {
        applyToAllMovies(function (movie :MovieClip) :void {
            setSkinAtInternal(movie, path, createDisplayObject);
        });
    }

    /**
     * Removes the skin, specified by 'path', of each movie registered with the AvatarBody.
     * (Equivalent to calling reskinMovies(path, null))
     */
    public function removeSkinAt (path :String) :void
    {
        setSkinAt(path, null);
    }

    /**
     * Reskins the specified node of a single movie.
     * @see #reskinMovies
     */
    public function set1SkinAt (movieName :String, path :String,
        createDisplayObject :Function = null) :void
    {
        for each (var movie :MovieClip in MovieList(_movies.get(movieName)).movies) {
            setSkinAtInternal(movie, path, createDisplayObject);
        }
    }

    /**
     * Removes the skin of the specified node of a single movie.
     */
    public function remove1SkinAt (movieName :String, path :String) :void
    {
        set1SkinAt(movieName, path, null);
    }

    /**
     * Reskins the specified node of the currently playing movie.
     * @see #reskinMovies
     */
    public function setCurrentMovieSkinAt (path :String, disp :DisplayObject = null) :void
    {
        setSkinAtInternal(_curMovie, path,
            function () :DisplayObject {
                return disp;
            });
    }

    /**
     * Returns the DisplayObject being used as the skin for the currently playing movie.
     */
    public function getCurrentMovieSkinAt (path :String) :DisplayObject
    {
        if (_curMovie != null) {
            var descendent :DisplayObjectContainer =
                DisplayUtil.getDescendent(_curMovie, path) as DisplayObjectContainer;
            if (descendent != null && descendent.numChildren > 0) {
                return descendent.getChildAt(0);
            }
        }
        return null;
    }

    /**
     * For each movie registered with the AvatarBody, applies the specified filters to that movie's
     * descendent, specified by 'path'. Ignores movies for which the descendent doesn't
     * exist.
     *
     * @param path the path used to find the nodes that will have the filters applied.
     *
     * @param filters an Array of BitmapFilters to apply to the nodes.
     */
    public function setFiltersAt (path :String, filters :Array = null) :void
    {
        applyToAllMovies(function (movie :MovieClip) :void {
            setFiltersAtInternal(movie, path, filters);
        });
    }

    /**
     * Reskins the specified node of a single movie.
     * @see #setFiltersAt
     */
    public function set1FiltersAt (movieName :String, path :String, filters :Array = null) :void
    {
        for each (var movie :MovieClip in MovieList(_movies.get(movieName)).movies) {
            setFiltersAtInternal(movie, path, filters);
        }
    }

    /**
     * Returns the name of the currently playing movie, as it was registered in registerMovie()
     *
     * @param ignoreTransitions if true, and the Avatar is transitioning between movies,
     * return the name of hte movie that will play when the transition is complete.
     */
    public function getCurrentMovieName (ignoreTransitions :Boolean = false) :String
    {
        if (ignoreTransitions && inTransition()) {
            for each (var movieList :MovieList in _movieQueue) {
                if (!movieList.isTransition) {
                    return movieList.name;
                }
            }
            return null;
        } else {
            return (_playing != null ? _playing.name : null);
        }
    }

    /**
     * Updates the avatar, playing new movies that need to be played. By default, this
     * is called on the ENTER_FRAME event.
     */
    protected function updateBody (...ignored) :void
    {
        if (_playing == null) {
            return;
        }

        if ((_curMovie != _playing.current) ||
            (_curMovie != null && _curMovie.currentFrame == _curMovie.totalFrames)) {

            // Get the next scene
            if (_movieQueue.length > 0) {
                _playing = (_movieQueue.shift() as MovieList);
            } else {
                _playing.update();
            }

            if (_playing.current != _curMovie) {
                // Remove the currently-playing movie
                if (_curMovie != null) {
                    removeChild(_curMovie);
                    _curMovie = null;
                }

                // And play the new one
                if (_playing.current != null) {
                    _curMovie = _playing.current;
                    _curMovie.x = _playing.currentLoc.x;
                    _curMovie.y = _playing.currentLoc.y;
                    addChild(_curMovie);

                    playMovie(_curMovie);
                }
            }
        }
    }

    /**
     * Subclasses can override this to do implementation-specific things when a new movie is played
     */
    protected function playMovie (movie :MovieClip) :void
    {
        movie.gotoAndPlay(1);
    }

    /**
     * Queues animations that transition between the specified states/actions. If a direct
     * transition is available, it will be used, otherwise we transition through "default".
     *
     * @return :Boolean If we queued a transition, return true.
     */
    protected function queueTransitions (from :String, to :String, immediate :Boolean) :Boolean
    {
        // queue our transition animation (direct if we have one, through 'default' if we don't)
        var direct :MovieList = getMovie(from + "_to_" + to);
        if (direct != null) {
            queueMovie(direct, immediate);
            return true;
        } else {
            return false;
        }
    }

    /**
     * Queues a movie up to be played as soon as the other scenes in the queue have completed.
     * Handles queueing of null movies by ignoring the request to simplify other code.
     */
    protected function queueMovie (movieList :MovieList, immediate :Boolean) :void
    {
        if (movieList == null) {
            return;

        } else if (_playing == null || immediate) {
            _movieQueue.length = 0;
            _playing = movieList;
            _playing.update();
            _movieQueue.push(movieList);

        } else {
            _movieQueue.push(movieList);
        }
    }

    protected function getMovie (key :String) :MovieList
    {
        return _movies.get(key.toLowerCase()) as MovieList;
    }

    protected function getAllMovies () :Array
    {
        var movies :Array = [];
        for each (var movieList :MovieList in _movies.values()) {
            for each (var movie :MovieClip in movieList.movies) {
                movies.push(movie);
            }
        }

        return movies;
    }

    protected function applyToAllMovies (f :Function) :void
    {
        _movies.forEach(
            function (name :String, movieList :MovieList) :void {
                for each (var movie :MovieClip in movieList.movies) {
                    f(movie);
                }
            });
    }

    protected function setSkinAtInternal (movie :MovieClip, path :String,
        createDisplayObject :Function = null)
        :void
    {
        var node :DisplayObjectContainer =
            DisplayUtil.getDescendent(movie, path) as DisplayObjectContainer;
        if (node != null) {
            var skin :DisplayObject = (createDisplayObject != null ? createDisplayObject() : null);
            reskinNode(node, skin);
        }
    }

    protected function reskinNode (node :DisplayObjectContainer, skin :DisplayObject = null) :void
    {
        // clear existing skin
        DisplayUtil.removeAllChildren(node);

        if (skin != null) {
            // If the skin (or its children) have animations, reset them.
            var animated :Boolean;
            DisplayUtil.applyToHierarchy(skin,
                function (d :DisplayObject) :void {
                    if (d is MovieClip) {
                        var mc :MovieClip = MovieClip(d);
                        if (mc.totalFrames > 1) {
                            mc.gotoAndPlay(1);
                            animated = true;
                        }
                    }
                });

            // TODO: is this necessary? Why?
            if (animated) {
                var holder :Sprite = new Sprite();
                holder.addChild(skin);
                skin = holder;
            }

            node.addChild(skin);
        }
    }

    protected function setFiltersAtInternal (movie :MovieClip, path :String, filters :Array = null)
        :void
    {
        var node :DisplayObjectContainer =
            DisplayUtil.getDescendent(movie, path) as DisplayObjectContainer;
        if (node != null) {
            setNodeFilters(node, filters);
        }
    }

    protected function setNodeFilters (node :DisplayObjectContainer, filters :Array = null) :void
    {
        if (filters == null) {
            filters = [];
        }

        // TODO: is this sufficient?
        // node.filters = filters;

        var numChildren :int = node.numChildren;
        for (var ii :int = 0; ii < numChildren; ++ii) {
            var child :DisplayObject = node.getChildAt(ii);
            child.filters = filters;
        }
    }

    protected var _movies :Map = Maps.newMapOf(String); // Map<name, MovieList>
    protected var _state :String;
    protected var _playing :MovieList;
    protected var _movieQueue :Array = [];
    protected var _curMovie :MovieClip;
    protected var _events :EventHandlerManager = new EventHandlerManager();

    protected static const log :Log = Log.getLog(YogaBody);
}
}

import com.threerings.util.Random;

import flash.display.MovieClip;
import flash.geom.Point;

class MovieList
{
    public function MovieList (name :String, isTransition :Boolean, movie :MovieClip,
        loc :Point, weight :int = 1)
    {
        _name = name;
        _isTransition = isTransition;
        addMovie(movie, loc, weight);
    }

    public function addMovie (movie :MovieClip, loc :Point, weight :int = 1) :void
    {
        _movies.push(movie);
        _locs.push(loc);
        _weights.push(weight);
        _totalWeight += weight;
    }

    public function update () :void
    {
        var value :int = _rando.nextInt(_totalWeight);
        for (var ii :int = 0; ii < _movies.length; ii++) {
            if (value < int(_weights[ii])) {
                _curidx = ii;
                return;
            }
            value -= int(_weights[ii]);
        }
    }

    public function get name () :String
    {
        return _name;
    }

    public function get isTransition () :Boolean
    {
        return _isTransition;
    }

    public function get current () :MovieClip
    {
        return (_movies[_curidx] as MovieClip);
    }

    public function get currentLoc () :Point
    {
        return (_locs[_curidx] as Point);
    }

    public function get movies () :Array
    {
        return _movies;
    }

    protected var _name :String;
    protected var _isTransition :Boolean;
    protected var _movies :Array = [];
    protected var _weights :Array = [];
    protected var _locs :Array = [];
    protected var _totalWeight :int = 0;

    protected var _curidx :int;

    protected var _rando :Random = new Random();
}
