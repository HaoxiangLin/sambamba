/*
    This file is part of Sambamba.
    Copyright (C) 2017 Pjotr Prins <pjotr.prins@thebird.nl>

    Sambamba is free software; you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published
    by the Free Software Foundation; either version 2 of the License,
    or (at your option) any later version.

    Sambamba is distributed in the hope that it will be useful, but
    WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
    General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program; if not, write to the Free Software
    Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA
    02111-1307 USA

*/
module bio2.pileup;

import std.exception;
import std.stdio;

import std.experimental.logger;

import sambamba.bio2.constants;

immutable ulong DEFAULT_BUFFER_SIZE = 1_000_000;


/**
   Cyclic buffer or ringbuffer based on Artem's original. Uses copy
   semantics to copy a read in a pre-allocated buffer. New items get
   added to the tail, and used items get popped from the head
   (FIFO). Basically it is empty when pointers align and full when
   head - tail equals length. Not that the pointers are of size_t
   which puts a theoretical limit on the number of items that can be
   pushed.
*/

import core.stdc.string : memcpy;

// alias ulong RingBufferIndex;

struct RingBufferIndex {
  alias Representation = ulong;
  private ulong value = 0;

  this(ulong v) {
    value = v;
  }

  // @disable this(this); // disable copy semantics;

  auto get() inout {
    return value;
  }

  auto max() @property {
    return value.max;
  }

  void opAssign(U)(U rhs) if (is(typeof(Checked!(T, Hook)(rhs)))) {
    value = rhs;
  }

  bool opEquals(U, this _)(U rhs) {
    return value == rhs;
  }

  auto opCmp(U, this _)(const U rhs) {
    return value < rhs ? -1 : value > rhs;
  }

  ulong opUnary(string s)() if (s == "++") {
    return ++value;
  }

}


struct RingBuffer(T) {

  T[] _items;
  RingBufferIndex _head;
  RingBufferIndex _tail;

  /** initializes round buffer of size $(D n) */
  this(size_t n) {
    _items = new T[n];
    // _items.reserve(n);
  }

  @disable this(this); // disable copy semantics;

  /*
  Does not work because data is no longer available!
  ~this() {
    // assert(is_empty); // make sure all items have been popped
  }
  */

  bool empty() @property @nogc nothrow const {
    return _tail == _head;
  }

  alias empty is_empty;

  auto ref front() @property {
    enforce(!is_empty, "ringbuffer is empty");
    return _items[_head.get() % $];
  }

  auto ref back() @property {
    enforce(!is_empty, "ringbuffer is empty");
    return _items[(_tail.get() - 1) % $];
  }

  bool is_tail(RingBufferIndex idx) {
    return idx == _tail.get()-1;
  }

  ref T read_at(RingBufferIndex idx) {
    enforce(!is_empty, "ringbuffer is empty");
    enforce(idx >= _head, "ringbuffer range error (idx before front)");
    enforce(idx != _tail, "ringbuffer range error (idx at end)");
    enforce(idx < _tail, "ringbuffer range error (idx after end)");
    return _items[idx.get() % $];
  }

  // This function is a hack.
  void update_at(RingBufferIndex idx, T item) {
    enforce(!is_empty, "ringbuffer is empty");
    enforce(idx >= _head, "ringbuffer range error (idx before front)");
    enforce(idx != _tail, "ringbuffer range error (idx at end)");
    enforce(idx < _tail, "ringbuffer range error (idx after end)");
    _items[idx.get() % $] = item; // uses copy semantics
  }

  RingBufferIndex popFront() {
    enforce(!is_empty, "ringbuffer is empty");
    ++_head.value;
    return _head;
  }

  /// Puts item on the stack and returns the index
  RingBufferIndex put(T item) {
    enforce(!is_full, "ringbuffer is full - you need to expand buffer");
    enforce(_tail < _tail.max, "ringbuffer overflow");
    _items[_tail.get() % $] = item; // uses copy semantics
    auto prev = _tail;
    ++_tail.value;
    return prev;
  }

  ulong length() @property const {
    // writeln(_tail.get(),":",_head.get(),"= len ",_tail.get()-_head.get());
    return _tail.get() - _head.get();
  }

  bool is_full() @property const {
    return _items.length == length();
  }

  RingBufferIndex pushed() @property const {
    return _tail;
  }
  RingBufferIndex popped() @property const {
    return _head;
  }

}

unittest {
    auto buf = RingBuffer!int(4);
    assert(buf.is_empty);

    buf.put(1);
    buf.put(2);
    assert(buf.length == 2);
    assert(buf.front == 1);
    buf.popFront(); // 1
    buf.popFront(); // 2
    buf.put(2);
    buf.put(1);
    buf.put(0);
    buf.put(3);
    assert(buf.is_full);
    assert(buf.front == 2);
    buf.popFront();
    assert(buf.front == 1);
    buf.put(4);
    buf.popFront();
    assert(buf.front == 0);
    buf.popFront();
    assert(buf.front == 3);
    buf.popFront();
    assert(buf.front == 4);
    buf.popFront();
    assert(buf.is_empty);
}

/**
   Represent a pileup of reads in a buffer.
*/

class PileUp(R) {
  RingBuffer!R ring;

  this(ulong bufsize=DEFAULT_BUFFER_SIZE) {
    ring = RingBuffer!R(bufsize);
  }

  RingBufferIndex push(R r) { return ring.put(r); }
  bool empty() @property const { return ring.is_empty();}
  ref R front() { return ring.front(); }
  bool idx_at_end(RingBufferIndex idx) { return ring.is_tail(idx); }
  ref R read_at_idx(RingBufferIndex idx) {
    return ring.read_at(idx);
  }

  void update_read_at_index(RingBufferIndex idx, R read) {
    ring.update_at(idx,read);
  }

  RingBufferIndex get_next_idx(RingBufferIndex idx) {
    idx.value += 1;
    return idx;
  }

  RingBufferIndex popFront() {
    return ring.popFront();
  }

  bool is_past_end(RingBufferIndex idx) {
    return (idx > ring._tail);
  }

}
