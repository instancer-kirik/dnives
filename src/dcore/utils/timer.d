module dcore.utils.timer;

import std.datetime;
import core.time;
import core.thread;
import std.algorithm;

/**
 * Timer utility class for delayed and periodic execution
 */
class Timer {
    private Duration _interval;           // Interval for timer
    private bool delegate() _callback;    // Callback to execute
    private MonoTime _lastExecution;      // Last execution time
    private bool _running;                // Is timer running
    private bool _repeat;                 // Should timer repeat
    private Thread _timerThread;          // Timer thread
    
    /**
     * Check if timer is currently active
     */
    @property bool isActive() {
        return _running;
    }
    
    /**
     * Constructor
     * Params:
     *   interval = Interval in milliseconds
     *   callback = Callback function to execute
     *   repeat = Whether to repeat the timer (true) or execute once (false)
     */
    this(long interval, bool delegate() callback, bool repeat = false) {
        _interval = dur!"msecs"(interval);
        _callback = callback;
        _repeat = repeat;
        _running = false;
    }
    
    /**
     * Start the timer
     * Returns: This timer instance for chaining
     */
    Timer start() {
        if (_running)
            return this;
            
        _running = true;
        _lastExecution = MonoTime.currTime;
        
        _timerThread = new Thread(&run);
        _timerThread.isDaemon = true;
        _timerThread.start();
        
        return this;
    }
    
    /**
     * Stop the timer
     * Returns: This timer instance for chaining
     */
    Timer stop() {
        _running = false;
        if (_timerThread && _timerThread.isRunning) {
            _timerThread.join(false);
        }
        
        return this;
    }
    
    /**
     * Change the timer interval
     * Params:
     *   interval = New interval in milliseconds
     * Returns: This timer instance for chaining
     */
    Timer setInterval(long interval) {
        _interval = dur!"msecs"(interval);
        return this;
    }
    
    /**
     * Check if timer is running
     * Returns: true if timer is running
     */
    bool isRunning() {
        return _running;
    }
    
    /**
     * Set repeat mode
     * Params:
     *   repeat = Whether timer should repeat
     * Returns: This timer instance for chaining
     */
    Timer setRepeat(bool repeat) {
        _repeat = repeat;
        return this;
    }
    
    /**
     * Private timer run method
     */
    private void run() {
        while (_running) {
            auto now = MonoTime.currTime;
            auto elapsed = now - _lastExecution;
            
            if (elapsed >= _interval) {
                _lastExecution = now;
                
                bool result = false;
                if (_callback)
                    result = _callback();
                    
                if (!_repeat || result) {
                    _running = false;
                    break;
                }
            }
            
            // Sleep for a short time to avoid high CPU usage
            Thread.sleep(dur!"msecs"(min(10, _interval.total!"msecs")));
        }
    }
}