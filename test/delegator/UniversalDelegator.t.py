import unittest

import sim


class CheckpointTests(unittest.TestCase):
    def tearDown(self):
        sim.CURRENT_TIME = 0

    def test_checkpoint_tracks_history_and_defaults(self):
        checkpoint = sim.Checkpoint[int](default=0)
        self.assertEqual(checkpoint.latest(), 0)

        checkpoint.push(5, 10)
        checkpoint.push(7, 20)

        self.assertEqual(checkpoint.lower_bound(4), 0)
        self.assertEqual(checkpoint.lower_bound(5), 10)
        self.assertEqual(checkpoint.lower_bound(6), 10)
        self.assertEqual(checkpoint.lower_bound(7), 20)
        self.assertEqual(checkpoint.lower_bound(9), 20)
        self.assertEqual(checkpoint.latest(), 20)


class DelegatorTests(unittest.TestCase):
    def setUp(self):
        sim.CURRENT_TIME = 0
        self.delegator = sim.Delegator(delay=3)

    def tearDown(self):
        sim.CURRENT_TIME = 0

    def test_slot_allocation_partial_fill(self):
        self.delegator.on_deposit(100)
        self.delegator.slot_add(30, "alice")
        self.delegator.slot_add(500, "bob")

        self.assertEqual(self.delegator.get_current_unallocated(), 0)
        self.assertEqual(self.delegator.get_slot_allocation_by_owner(0, "alice"), 30)
        self.assertEqual(self.delegator.get_slot_allocation_by_owner(0, "bob"), 70)
        self.assertEqual(self.delegator.get_slot_order(1), 1)

    def test_slot_allocation_partial_fill_2(self):
        self.delegator.on_deposit(100)
        self.delegator.slot_add(500, "alice")
        self.delegator.slot_add(30, "bob")

        self.assertEqual(self.delegator.get_current_unallocated(), 0)
        self.assertEqual(self.delegator.get_slot_allocation_by_owner(0, "alice"), 100)
        self.assertEqual(self.delegator.get_slot_allocation_by_owner(0, "bob"), 0)
        self.assertEqual(self.delegator.get_slot_order(1), 1)

    def test_slot_allocation_respects_order_and_limits(self):
        self.delegator.on_deposit(100)
        self.delegator.slot_add(30, "alice")
        self.delegator.slot_add(50, "bob")

        self.assertEqual(self.delegator.get_current_unallocated(), 20)
        self.assertEqual(self.delegator.get_slot_allocation_by_owner(0, "alice"), 30)
        self.assertEqual(self.delegator.get_slot_allocation_by_owner(0, "bob"), 50)
        self.assertEqual(self.delegator.get_slot_order(1), 1)

    def test_increase_limit_consumes_unallocated_and_updates_prev_sums(self):
        self.delegator.on_deposit(100)
        self.delegator.slot_add(30, "alice")
        self.delegator.slot_add(50, "bob")

        sim.CURRENT_TIME = 1
        self.assertTrue(self.delegator.slot_increase_limit(0, 15))
        self.assertEqual(self.delegator.slots[0].get_limit(1), 45)
        self.assertEqual(self.delegator.slots[1].get_prev_sum(1), 45)
        self.assertEqual(self.delegator.get_slot_allocation_by_owner(1, "alice"), 45)
        self.assertEqual(self.delegator.get_current_unallocated(), 5)

    def test_decrease_limit_schedules_pending_free_until_delay_expires(self):
        self.delegator.on_deposit(100)
        self.delegator.slot_add(60, "alice")
        self.delegator.slot_add(30, "bob")

        sim.CURRENT_TIME = 1
        self.assertTrue(self.delegator.slot_decrease_limit(0, 20))
        self.assertEqual(self.delegator.slots[0].get_limit(1), 40)
        self.assertEqual(self.delegator.slots[1].get_prev_sum(1), 40)

        sim.CURRENT_TIME = 2
        self.assertEqual(self.delegator.get_available(2), 80)
        self.assertEqual(self.delegator.get_current_unallocated(), 10)

        sim.CURRENT_TIME = 4
        self.assertEqual(self.delegator.get_available(4), 100)
        self.assertEqual(self.delegator.get_slot_allocation_by_owner(4, "alice"), 40)
        self.assertEqual(self.delegator.get_slot_allocation_by_owner(4, "bob"), 30)
        self.assertEqual(self.delegator.get_current_unallocated(), 30)


if __name__ == "__main__":
    unittest.main()
