#!/usr/bin/python
# Copyright 2011 Zuse Institute Berlin
#
#    Licensed under the Apache License, Version 2.0 (the "License");
#    you may not use this file except in compliance with the License.
#    You may obtain a copy of the License at
#
#        http://www.apache.org/licenses/LICENSE-2.0
#
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS,
#    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#    See the License for the specific language governing permissions and
#    limitations under the License.

import unittest
import TransactionSingleOpTest, TransactionTest
import sys

if __name__ == '__main__':
    suite = unittest.TestLoader().loadTestsFromNames(['TransactionSingleOpTest.TestTransactionSingleOp',
                                                      'TransactionTest.TestTransaction',
                                                      'ReplicatedDHTTest.TestReplicatedDHT',
                                                      'PubSubTest.TestPubSub'])
    if not unittest.TextTestRunner(verbosity=2).run(suite).wasSuccessful():
        sys.exit(1)