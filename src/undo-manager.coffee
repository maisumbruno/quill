Scribe = require('./scribe')
Tandem = require('tandem-core')


getLastChangeIndex = (delta) ->
  lastChangeIndex = index = offset = 0
  _.each(delta.ops, (op) ->
    # Insert
    if Tandem.Delta.isInsert(op)
      offset += op.getLength()
      lastChangeIndex = index + offset
    else if Tandem.Delta.isRetain(op)
      # Delete
      if op.start > index
        lastChangeIndex = index + offset
        offset -= (op.start - index)
      # Format
      if _.keys(op.attributes).length > 0
        lastChangeIndex = op.end + offset
      index = op.end
  )
  if delta.endLength < delta.startLength + offset
    lastChangeIndex = delta.endLength
  return lastChangeIndex

_ignoreChanges = (fn) ->
  oldIgnoringChanges = @ignoringChanges
  @ignoringChanges = true
  fn.call(this)
  @ignoringChanges = oldIgnoringChanges


class Scribe.UndoManager
  @DEFAULTS:
    delay: 1000
    maxStack: 100


  constructor: (@editor, options = {}) ->
    this.clear()
    @options = _.defaults(options, Scribe.UndoManager.DEFAULTS)
    @lastRecorded = 0
    this.initListeners()

  initListeners: ->
    @editor.keyboard.addHotkey(Scribe.Keyboard.HOTKEYS.UNDO, =>
      this.undo()
    )
    @editor.keyboard.addHotkey(Scribe.Keyboard.HOTKEYS.REDO, =>
      this.redo()
    )
    @ignoringChanges = false
    @editor.on(Scribe.Editor.events.USER_TEXT_CHANGE, (delta) =>
      this.record(delta, @oldDelta) unless @ignoringChanges
      @oldDelta = @editor.getDelta()
    ).on(Scribe.Editor.events.API_TEXT_CHANGE, (delta) =>
      this.transformExternal(delta)
      @oldDelta = @editor.getDelta()
    )

  clear: ->
    @undoStack = []
    @redoStack = []
    @oldDelta = @editor.getDelta()

  record: (changeDelta, oldDelta) ->
    return if changeDelta.isIdentity()
    @redoStack = []
    undoDelta = oldDelta.invert(changeDelta)
    timestamp = new Date().getTime()
    if @lastRecorded + @options.delay > timestamp and @undoStack.length > 0
      change = @undoStack.pop()
      undoDelta = undoDelta.compose(change.undo)
      changeDelta = change.redo.compose(changeDelta)
    else
      @lastRecorded = timestamp
    @undoStack.push({
      redo: changeDelta
      undo: undoDelta
    })
    @undoStack.unshift() if @undoStack.length > @options.maxStack

  redo: ->
    if @redoStack.length > 0
      change = @redoStack.pop()
      _ignoreChanges.call(this, =>
        @editor.applyDelta(change.redo, { source: 'user' })
        index = getLastChangeIndex(change.redo)
        @editor.setSelection(new Scribe.Range(@editor, index, index))
      )
      @undoStack.push(change)

  transformExternal: (delta) ->
    return if delta.isIdentity()
    @undoStack = _.map(@undoStack, (change) ->
      return {
        redo: delta.follows(change.redo, true)
        undo: change.undo.follows(delta, true)
      }
    )

  undo: ->
    if @undoStack.length > 0
      change = @undoStack.pop()
      _ignoreChanges.call(this, =>
        @editor.applyDelta(change.undo, { source: 'user' })
        index = getLastChangeIndex(change.undo)
        @editor.setSelection(new Scribe.Range(@editor, index, index))
      )
      @redoStack.push(change)


module.exports = Scribe
