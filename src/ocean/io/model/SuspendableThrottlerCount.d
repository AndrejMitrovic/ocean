/*******************************************************************************

    Helper classes to manage the situations where a set of objects implementing
    ISuspendable should be throttled based on a count of pending items of
    some kind. For example, one common situation of this type is as follows:

        1. You are streaming data from one or more ISuspendable sources.
        2. For each chunk of data received you wish to do some processing which
           will not finish immediately. (Thus the received data need to be kept
           around in some way, forming a set of 'pending items'.)
        3. The ISuspendables which are providing the input data must be
           throttled (i.e. suspended and resumed) based on the number of pending
           items.

    Copyright:
        Copyright (c) 2009-2016 dunnhumby Germany GmbH.
        All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE_BOOST.txt for details.
        Alternatively, this file may be distributed under the terms of the Tango
        3-Clause BSD License (see LICENSE_BSD.txt for details).

*******************************************************************************/

module ocean.io.model.SuspendableThrottlerCount;



import ocean.transition;
import ocean.core.Verify;

import ocean.io.model.ISuspendable,
       ocean.io.model.ISuspendableThrottler,
       ocean.util.container.AppendBuffer;

import ocean.core.Array : contains;

debug import ocean.io.Stdout;


/*******************************************************************************

    Simple suspendable throttler which just counts the number of pending items,
    and throttles the suspendables based on that count. No data other than the
    pending count is stored.

*******************************************************************************/

public class SuspendableThrottlerCount : ISuspendableThrottlerCount
{
    /***************************************************************************

        Number of items pending.

    ***************************************************************************/

    private size_t count;


    /***************************************************************************

        Constructor.

        Params:
            suspend_point = point at which the suspendables are suspended
            resume_point = point at which the suspendables are resumed

    ***************************************************************************/

    public this ( size_t suspend_point, size_t resume_point )
    {
        super(suspend_point, resume_point);
    }


    /***************************************************************************

        Increases the count of pending items and throttles the suspendables.

    ***************************************************************************/

    public void inc ( )
    {
        verify(this.count < this.count.max);

        this.count++;
        super.throttledSuspend();
    }

    /// ditto
    public void opUnary ( string op ) ( ) if (op == "++")
    {
        return this.inc();
    }

    // WORKAROUND: DMD 2.068 had difficulties  resolving multiple overloads of
    // `add` when one came from alias and other was "native" method. Creating
    // distinct name (`inc`) allowed to disambugate it manually
    public alias inc add;


    /***************************************************************************

        Increases the count of pending items and throttles the suspendables.

        Params:
            n = number of pending items to add

    ***************************************************************************/

    public void add ( size_t n )
    {
        verify(this.count <= this.count.max - n);

        this.count += n;
        super.throttledSuspend();
    }

    /// ditto
    public void opOpAssign ( string op ) ( size_t n ) if (op == "+")
    {
        this.add(n);
    }


    /***************************************************************************

        Decreases the count of pending items and throttles the suspendables.

    ***************************************************************************/

    public void dec ( )
    {
        verify(this.count > 0);

        this.count--;
        super.throttledResume();
    }

    /// ditto
    public void opUnary ( string op ) ( ) if (op == "--")
    {
        return this.dec();
    }

    // WORKAROUND: DMD 2.068 had difficulties  resolving multiple overloads of
    // `remove` when one came from alias and other was "native" method. Creating
    // distinct name (`dec`) allowed to disambugate it manually
    public alias dec remove;


    /***************************************************************************

        Decreases the count of pending items and throttles the suspendables.

        Params:
            n = number of pending items to remove

    ***************************************************************************/

    public void remove ( size_t n )
    {
        verify(this.count >= n);
        this.count -= n;
        super.throttledResume();
    }

    /// ditto
    public void opOpAssign ( string op ) ( size_t n ) if (op == "-")
    {
        this.remove(n);
    }


    /***************************************************************************

        Returns:
            the number of pending items

    ***************************************************************************/

    override public size_t length ( )
    {
        return this.count;
    }
}

unittest
{
    import ocean.core.Test : test;

    // Helper class to allow us to test operator overloads
    // without touching other parts of the class logic
    static class OpsTest : SuspendableThrottlerCount
    {
        this ()
        {
            size_t suspend_point = 8;
            size_t resume_point = 3;
            super(suspend_point, resume_point);
        }

        override void inc () { this.count++; }
        override void dec () { this.count--; }

        override void add (size_t n) { this.count += n; }
        override void remove (size_t n) { this.count -= n; }
    }

    scope ops_test = new OpsTest;
    test!"=="(ops_test.length, 0);

    ops_test++;
    test!"=="(ops_test.length, 1);
    test(!ops_test.suspend);
    test(ops_test.resume);

    ops_test += 7;
    test!"=="(ops_test.length, 8);
    test(ops_test.suspend);
    test(!ops_test.resume);

    ops_test--;
    test!"=="(ops_test.length, 7);
    test(!ops_test.suspend);
    test(!ops_test.resume);

    ops_test -= 4;
    test!"=="(ops_test.length, 3);
    test(!ops_test.suspend);
    test(ops_test.resume);
}


/*******************************************************************************

    SuspendableThrottlerCount unittest.

*******************************************************************************/

unittest
{
    static class SuspendableThrottlerCount_Test : ISuspendableThrottlerCount_Test
    {
        private SuspendableThrottlerCount count;

        this ( )
        {
            this.count = new SuspendableThrottlerCount(this.suspend, this.resume);
            super(this.count);
        }

        override void inc ( )
        {
            this.count++;
        }

        override void dec ( )
        {
            this.count--;
        }
    }

    scope test = new SuspendableThrottlerCount_Test;
}


/*******************************************************************************

    Abstract base class for suspendable throttlers which throttle based on a
    count of pending items of some kind.

    Provides the following additional functionality:
        * An abstract length() method which determines the current count of
          pending items.
        * suspend() and resume() methods which suspend or resume the
          ISuspendables based on the count of pending items and the suspend and
          resume points defined in the constructor.

*******************************************************************************/

abstract public class ISuspendableThrottlerCount : ISuspendableThrottler
{
    /***************************************************************************

        When the number of pending items reaches this value or greater, the
        suspendables will be suspended.

    ***************************************************************************/

    public const(size_t) suspend_point;


    /***************************************************************************

        When the number of pending items reaches this value or less, the
        suspendables will be resumed.

    ***************************************************************************/

    public const(size_t) resume_point;


    /***************************************************************************

        Constructor.

        Params:
            suspend_point = point at which the suspendables are suspended
            resume_point = point at which the suspendables are resumed

    ***************************************************************************/

    public this ( size_t suspend_point, size_t resume_point )
    {
        verify(suspend_point > resume_point);

        this.suspend_point = suspend_point;
        this.resume_point = resume_point;
    }


    /***************************************************************************

        Returns:
            the number of pending items

    ***************************************************************************/

    abstract public size_t length ( );


    /***************************************************************************

        Decides whether the suspendables should be suspended. Called by
        throttle() when not suspended.

        If the number of pending items is greater than the suspend point
        specified in the constructor, then the suspendables are suspended,
        stopping the input.

        Returns:
            true if the suspendables should be suspeneded

    ***************************************************************************/

    override protected bool suspend ( )
    {
        return this.length >= this.suspend_point;
    }


    /***************************************************************************

        Decides whether the suspendables should be resumed. Called by
        throttle() when suspended.

        If the number of pending items is less than the resume point specified
        in the constructor, then the suspendables are resumed, restarting the
        input.

        Returns:
            true if the suspendables should be resumed

    ***************************************************************************/

    override protected bool resume ( )
    {
        return this.length <= this.resume_point;
    }
}


/*******************************************************************************

    Abstract base class which tests an ISuspendableThrottlerCount instance. The
    abstract inc() and dec() methods (which increment and decrement the count)
    must be implemented.

*******************************************************************************/

version (unittest)
{
    private import ocean.core.Test;

    abstract class ISuspendableThrottlerCount_Test
    {
        static immutable suspend = 10;
        static immutable resume = 2;

        protected ISuspendableThrottlerCount throttler;

        this ( ISuspendableThrottlerCount throttler )
        {
            this.throttler = throttler;

            // Fill up throttler to one before suspension
            for ( int i; i < suspend - 1; i++ )
            {
                this.inc();
                test(!this.throttler.suspended);
            }

            // Next increment should suspend
            this.inc();
            test(this.throttler.suspended);

            // Empty throttler to one before resumption
            static immutable diff = suspend - resume;
            for ( int i; i < diff - 1; i++ )
            {
                this.dec();
                test(this.throttler.suspended);
            }

            // Next decrement should resume
            this.dec();
            test(!this.throttler.suspended);
        }

        abstract void inc ( );
        abstract void dec ( );
    }
}
