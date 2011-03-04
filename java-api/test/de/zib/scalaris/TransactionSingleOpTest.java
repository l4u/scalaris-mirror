/**
 *  Copyright 2007-2011 Zuse Institute Berlin
 *
 *   Licensed under the Apache License, Version 2.0 (the "License");
 *   you may not use this file except in compliance with the License.
 *   You may obtain a copy of the License at
 *
 *       http://www.apache.org/licenses/LICENSE-2.0
 *
 *   Unless required by applicable law or agreed to in writing, software
 *   distributed under the License is distributed on an "AS IS" BASIS,
 *   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 *   See the License for the specific language governing permissions and
 *   limitations under the License.
 */
package de.zib.scalaris;

import static org.junit.Assert.assertTrue;
import static org.junit.Assert.assertEquals;

import org.junit.Test;

import com.ericsson.otp.erlang.OtpErlangAtom;
import com.ericsson.otp.erlang.OtpErlangObject;
import com.ericsson.otp.erlang.OtpErlangString;
import com.ericsson.otp.erlang.OtpErlangTuple;

/**
 * Unit test for the {@link TransactionSingleOp} class.
 * 
 * @author Nico Kruber, kruber@zib.de
 * @version 2.7
 * @since 2.0
 */
public class TransactionSingleOpTest {
	private final static long testTime = System.currentTimeMillis();
	
	private final static String[] testData = {
		"ahz2ieSh", "wooPhu8u", "quai9ooK", "Oquae4ee", "Airier1a", "Boh3ohv5", "ahD3Saog", "EM5ooc4i", 
		"Epahrai8", "laVahta7", "phoo6Ahj", "Igh9eepa", "aCh4Lah6", "ooT0ath5", "uuzau4Ie", "Iup6mae6", 
//		"xie7iSie", "ail8yeeP", "ooZ4eesi", "Ahn7ohph", "Ohy5moo6", "xooSh9Oo", "ieb6eeS7", "Thooqu9h", 
//		"eideeC9u", "phois3Ie", "EimaiJ2p", "sha6ahR1", "Pheih3za", "bai4eeXe", "rai0aB7j", "xahXoox6", 
//		"Xah4Okeg", "cieG8Yae", "Pe9Ohwoo", "Eehig6ph", "Xe7rooy6", "waY2iifu", "kemi8AhY", "Che7ain8", 
//		"ohw6seiY", "aegh1oBa", "thoh9IeG", "Kee0xuwu", "Gohng8ee", "thoh9Chi", "aa4ahQuu", "Iesh5uge", 
//		"Ahzeil8n", "ieyep5Oh", "xah3IXee", "Eefa5qui", "kai8Muuf", "seeCe0mu", "cooqua5Y", "Ci3ahF6z", 
//		"ot0xaiNu", "aewael8K", "aev3feeM", "Fei7ua5t", "aeCa6oph", "ag2Aelei", "Shah1Pho", "ePhieb0N", 
//		"Uqu7Phup", "ahBi8voh", "oon3aeQu", "Koopa0nu", "xi0quohT", "Oog4aiph", "Aip2ag5D", "tirai7Ae", 
//		"gi0yoePh", "uay7yeeX", "aeb6ahC1", "OoJeic2a", "ieViom1y", "di0eeLai", "Taec2phe", "ID2cheiD", 
//		"oi6ahR5M", "quaiGi8W", "ne1ohLuJ", "DeD0eeng", "yah8Ahng", "ohCee2ie", "ecu1aDai", "oJeijah4", 
//		"Goo9Una1", "Aiph3Phi", "Ieph0ce5", "ooL6cae7", "nai0io1H", "Oop2ahn8", "ifaxae7O", "NeHai1ae", 
//		"Ao8ooj6a", "hi9EiPhi", "aeTh9eiP", "ao8cheiH", "Yieg3sha", "mah7cu2D", "Uo5wiegi", "Oowei0ya", 
//		"efeiDee7", "Oliese6y", "eiSh1hoh", "Joh6hoh9", "zib6Ooqu", "eejiJie4", "lahZ3aeg", "keiRai1d", 
//		"Fei0aewe", "aeS8aboh", "hae3ohKe", "Een9ohQu", "AiYeeh7o", "Yaihah4s", "ood4Giez", "Oumai7te", 
//		"hae2kahY", "afieGh4v", "Ush0boo0", "Ekootee5", "Ya8iz6Ie", "Poh6dich", "Eirae4Ah", "pai8Eeme", 
//		"uNah7dae", "yo3hahCh", "teiTh7yo", "zoMa5Cuv", "ThiQu5ax", "eChi5caa", "ii9ujoiV", "ge7Iekui", 
		"sai2aiTa", "ohKi9rie", "ei2ioChu", "aaNgah9y", "ooJai1Ie", "shoh0oH9", "Ool4Ahya", "poh0IeYa", 
		"Uquoo0Il", "eiGh4Oop", "ooMa0ufe", "zee6Zooc", "ohhao4Ah", "Uweekek5", "aePoos9I", "eiJ9noor", 
		"phoong1E", "ianieL2h", "An7ohs4T", "Eiwoeku3", "sheiS3ao", "nei5Thiw", "uL5iewai", "ohFoh9Ae"};
	
	static {
		// set not to automatically try reconnects (auto-retries prevent ConnectionException tests from working): 
		((DefaultConnectionPolicy) ConnectionFactory.getInstance().getConnectionPolicy()).setMaxRetries(0);
	}

	/**
	 * Test method for
	 * {@link TransactionSingleOp#TransactionSingleOp()}.
	 * @throws ConnectionException 
	 */
	@Test
	public void testTransactionSingleOp1() throws ConnectionException {
		TransactionSingleOp conn = new TransactionSingleOp();
		conn.closeConnection();
	}
	
	/**
	 * Test method for
	 * {@link TransactionSingleOp#TransactionSingleOp(Connection)}.
	 * @throws ConnectionException 
	 */
	@Test
	public void testTransactionSingleOp2() throws ConnectionException {
		TransactionSingleOp conn = new TransactionSingleOp(ConnectionFactory.getInstance().createConnection("test"));
		conn.closeConnection();
	}

	/**
	 * Test method for {@link TransactionSingleOp#read(String)}.
	 * 
	 * @throws NotFoundException
	 * @throws UnknownException
	 * @throws TimeoutException
	 * @throws ConnectionException
	 */
	@Test(expected=NotFoundException.class)
	public void testRead_NotFound() throws ConnectionException,
			TimeoutException, UnknownException, NotFoundException {
		String key = "_Read_NotFound";
		TransactionSingleOp conn = new TransactionSingleOp();
		try {
			conn.read(testTime + key);
		} finally {
			conn.closeConnection();
		}
	}

	/**
	 * Test method for {@link TransactionSingleOp#read(OtpErlangString)}.
	 * 
	 * @throws NotFoundException
	 * @throws UnknownException
	 * @throws TimeoutException
	 * @throws ConnectionException
	 */
	@Test(expected=NotFoundException.class)
	public void testReadOtp_NotFound() throws ConnectionException,
			TimeoutException, UnknownException, NotFoundException {
		String key = "_ReadOtp_NotFound";
		TransactionSingleOp conn = new TransactionSingleOp();
		try {
			conn.read(new OtpErlangString(testTime + key));
		} finally {
			conn.closeConnection();
		}
	}

	/**
	 * Test method for {@link TransactionSingleOp#read(String)} with a closed connection.
	 * 
	 * @throws NotFoundException
	 * @throws UnknownException
	 * @throws TimeoutException
	 * @throws ConnectionException
	 */
	@Test(expected=ConnectionException.class)
	public void testRead_NotConnected() throws ConnectionException,
			TimeoutException, UnknownException, NotFoundException {
		String key = "_Read_NotConnected";
		TransactionSingleOp conn = new TransactionSingleOp();
		conn.closeConnection();
		conn.read(testTime + key);
	}

	/**
	 * Test method for {@link TransactionSingleOp#read(OtpErlangString)} with a
	 * closed connection.
	 * 
	 * @throws NotFoundException
	 * @throws UnknownException
	 * @throws TimeoutException
	 * @throws ConnectionException
	 */
	@Test(expected=ConnectionException.class)
	public void testReadOtp_NotConnected() throws ConnectionException,
			TimeoutException, UnknownException, NotFoundException {
		String key = "_ReadOtp_NotConnected";
		TransactionSingleOp conn = new TransactionSingleOp();
		conn.closeConnection();
		conn.read(new OtpErlangString(testTime + key));
	}

	/**
	 * Test method for
	 * {@link TransactionSingleOp#write(OtpErlangString, OtpErlangObject)} with a
	 * closed connection.
	 * 
	 * @throws UnknownException
	 * @throws TimeoutException
	 * @throws ConnectionException
	 * @throws NotFoundException
	 * @throws AbortException 
	 */
	@Test(expected=ConnectionException.class)
	public void testWriteOtp_NotConnected() throws ConnectionException,
			TimeoutException, UnknownException, NotFoundException, AbortException {
		String key = "_WriteOtp_NotConnected";
		TransactionSingleOp conn = new TransactionSingleOp();
		conn.closeConnection();
		OtpErlangObject[] data = new OtpErlangObject[] {
				new OtpErlangString(testData[0]),
				new OtpErlangString(testData[1]) };
		conn.write(
				new OtpErlangString(testTime + key),
				new OtpErlangTuple(data) );
	}
	
	/**
	 * Test method for
	 * {@link TransactionSingleOp#write(OtpErlangString, OtpErlangObject)}
	 * and {@link TransactionSingleOp#read(OtpErlangString)}.
	 * Writes erlang tuples and uses a distinct key for each value. Tries to read the data afterwards.
	 * 
	 * @throws UnknownException
	 * @throws TimeoutException
	 * @throws ConnectionException
	 * @throws NotFoundException 
	 * @throws AbortException 
	 */
	@Test
	public void testWriteOtp1() throws ConnectionException,
			TimeoutException, UnknownException, NotFoundException, AbortException {
		String key = "_WriteOtp1_";
		TransactionSingleOp conn = new TransactionSingleOp();

		try {
			for (int i = 0; i < testData.length - 1; i += 2) {
				OtpErlangObject[] data = new OtpErlangObject[] {
						new OtpErlangString(testData[i]),
						new OtpErlangString(testData[i + 1]) };
				conn.write(
						new OtpErlangString(testTime + key + i),
						new OtpErlangTuple(data) );
			}
			
			// now try to read the data:
			
			for (int i = 0; i < testData.length - 1; i += 2) {
				OtpErlangObject[] data = new OtpErlangObject[] {
						new OtpErlangString(testData[i]),
						new OtpErlangString(testData[i + 1]) };
				OtpErlangObject actual = conn.read(
						new OtpErlangString(testTime + key + i));
				OtpErlangTuple expected = new OtpErlangTuple(data);
				
				assertEquals(expected, actual);
			}
		} finally {
			conn.closeConnection();
		}
	}
	
	/**
	 * Test method for
	 * {@link TransactionSingleOp#write(OtpErlangString, OtpErlangObject)}
	 * and {@link TransactionSingleOp#read(OtpErlangString)}.
	 * Writes erlang tuples and uses a single key for all the values. Tries to read the data afterwards.
	 * 
	 * @throws UnknownException
	 * @throws TimeoutException
	 * @throws ConnectionException
	 * @throws NotFoundException 
	 * @throws AbortException 
	 */
	@Test
	public void testWriteOtp2() throws ConnectionException,
			TimeoutException, UnknownException, NotFoundException, AbortException {
		String key = "_WriteOtp2";
		TransactionSingleOp conn = new TransactionSingleOp();

		try {
			OtpErlangObject[] data = new OtpErlangObject[0];
			for (int i = 0; i < testData.length - 1; i += 2) {
				data = new OtpErlangObject[] {
						new OtpErlangString(testData[i]),
						new OtpErlangString(testData[i + 1]) };
				conn.write(
						new OtpErlangString(testTime + key),
						new OtpErlangTuple(data));
			}
			
			// now try to read the data:
			
			OtpErlangObject actual = conn.read(
					new OtpErlangString(testTime + key));
			OtpErlangTuple expected = new OtpErlangTuple(data);
			
			assertEquals(expected, actual);
		} finally {
			conn.closeConnection();
		}
	}

	/**
	 * Test method for {@link TransactionSingleOp#write(String, String)} with a
	 * closed connection.
	 * 
	 * @throws UnknownException
	 * @throws TimeoutException
	 * @throws ConnectionException
	 * @throws NotFoundException
	 * @throws AbortException 
	 */
	@Test(expected=ConnectionException.class)
	public void testWrite_NotConnected() throws ConnectionException,
			TimeoutException, UnknownException, NotFoundException, AbortException {
		String key = "_Write_NotConnected";
		TransactionSingleOp conn = new TransactionSingleOp();
		conn.closeConnection();
		conn.write(testTime + key, testData[0]);
	}
	
	/**
	 * Test method for
	 * {@link TransactionSingleOp#write(String, String)}
	 * and {@link TransactionSingleOp#read(String)}.
	 * Writes strings and uses a distinct key for each value. Tries to read the data afterwards.
	 * 
	 * @throws UnknownException
	 * @throws TimeoutException
	 * @throws ConnectionException
	 * @throws NotFoundException 
	 * @throws AbortException 
	 */
	@Test
	public void testWrite1() throws ConnectionException,
			TimeoutException, UnknownException, NotFoundException, AbortException {
		String key = "_Write1_";
		TransactionSingleOp conn = new TransactionSingleOp();
		
		try {
			for (int i = 0; i < testData.length; ++i) {
				conn.write(testTime + key + i, testData[i]);
			}
			
			// now try to read the data:
			for (int i = 0; i < testData.length; ++i) {
				String actual = conn.read(testTime + key + i).toString();
				assertEquals(testData[i], actual);
			}
		} finally {
			conn.closeConnection();
		}
	}
	
	/**
	 * Test method for
	 * {@link TransactionSingleOp#write(String, String)}
	 * and {@link TransactionSingleOp#read(String)}.
	 * Writes strings and uses a single key for all the values. Tries to read the data afterwards.
	 * 
	 * @throws UnknownException
	 * @throws TimeoutException
	 * @throws ConnectionException
	 * @throws NotFoundException 
	 * @throws AbortException 
	 */
	@Test
	public void testWrite2() throws ConnectionException,
			TimeoutException, UnknownException, NotFoundException, AbortException {
		String key = "_Write2";
		TransactionSingleOp conn = new TransactionSingleOp();

		try {
			for (int i = 0; i < testData.length; ++i) {
				conn.write(testTime + key, testData[i]);
			}
			
			// now try to read the data:
			String actual = conn.read(testTime + key).toString();
			assertEquals(testData[testData.length - 1], actual);
		} finally {
			conn.closeConnection();
		}
	}

    /**
     * Test method for
     * {@link TransactionSingleOp#testAndSet(OtpErlangString, OtpErlangObject, OtpErlangObject)}
     * with a closed connection.
     * 
     * @throws UnknownException
     * @throws TimeoutException
     * @throws ConnectionException
     * @throws NotFoundException
     * @throws AbortException 
     * @throws KeyChangedException 
     * 
     * @since 2.7
     */
    @Test(expected=ConnectionException.class)
    public void testTestAndSetOtp_NotConnected() throws ConnectionException,
            TimeoutException, UnknownException, NotFoundException, AbortException, KeyChangedException {
        String key = "_TestAndSetOtp_NotConnected";
        TransactionSingleOp conn = new TransactionSingleOp();
        conn.closeConnection();
        OtpErlangObject[] data = new OtpErlangObject[] {
                new OtpErlangString(testData[0]),
                new OtpErlangString(testData[1]) };
        conn.testAndSet(
                new OtpErlangString(testTime + key),
                new OtpErlangAtom("ok"),
                new OtpErlangTuple(data) );
    }
    
    /**
     * Test method for
     * {@link TransactionSingleOp#testAndSet(OtpErlangString, OtpErlangObject, OtpErlangObject)}.
     * Tries test_and_set with a non-existing key.
     * 
     * @throws UnknownException
     * @throws TimeoutException
     * @throws ConnectionException
     * @throws NotFoundException 
     * @throws AbortException 
     * @throws KeyChangedException 
     * 
     * @since 2.7
     */
    @Test(expected=NotFoundException.class)
    public void testTestAndSetOtp_NotFound() throws ConnectionException,
            TimeoutException, UnknownException, NotFoundException, AbortException, KeyChangedException {
        String key = "_TestAndSetOtp_NotFound";
        TransactionSingleOp conn = new TransactionSingleOp();

        try {
            OtpErlangObject[] data = new OtpErlangObject[] {
                    new OtpErlangString(testData[0]),
                    new OtpErlangString(testData[1]) };
            conn.testAndSet(
                    new OtpErlangString(testTime + key),
                    new OtpErlangAtom("ok"),
                    new OtpErlangTuple(data) );
        } finally {
            conn.closeConnection();
        }
    }
    
    /**
     * Test method for
     * {@link TransactionSingleOp#testAndSet(OtpErlangString, OtpErlangObject, OtpErlangObject)},
     * {@link TransactionSingleOp#read(OtpErlangString)}
     * and {@link TransactionSingleOp#write(OtpErlangString, OtpErlangObject)}.
     * Writes an erlang tuple and tries to overwrite it using test_and_set
     * knowing the correct old value. Tries to read the data afterwards.
     * 
     * @throws UnknownException
     * @throws TimeoutException
     * @throws ConnectionException
     * @throws NotFoundException 
     * @throws AbortException 
     * @throws KeyChangedException 
     * 
     * @since 2.7
     */
    @Test
    public void testTestAndSetOtp1() throws ConnectionException,
            TimeoutException, UnknownException, NotFoundException, AbortException, KeyChangedException {
        String key = "_TestAndSetOtp1";
        TransactionSingleOp conn = new TransactionSingleOp();

        try {
            // first write all values:
            for (int i = 0; i < testData.length - 1; i += 2) {
                OtpErlangObject[] data = new OtpErlangObject[] {
                        new OtpErlangString(testData[i]),
                        new OtpErlangString(testData[i + 1]) };
                conn.write(
                        new OtpErlangString(testTime + key + i),
                        new OtpErlangTuple(data));
            }
            
            // now try to overwrite them using test_and_set:
            for (int i = 0; i < testData.length - 1; i += 2) {
                OtpErlangObject[] old_data = new OtpErlangObject[] {
                        new OtpErlangString(testData[i]),
                        new OtpErlangString(testData[i + 1]) };
                OtpErlangObject[] new_data = new OtpErlangObject[] {
                        new OtpErlangString(testData[i + 1]),
                        new OtpErlangString(testData[i]) };
                conn.testAndSet(
                        new OtpErlangString(testTime + key + i),
                        new OtpErlangTuple(old_data),
                        new OtpErlangTuple(new_data));
            }
            
            // now try to read the data:
            for (int i = 0; i < testData.length - 1; i += 2) {
                OtpErlangObject[] data = new OtpErlangObject[] {
                        new OtpErlangString(testData[i + 1]),
                        new OtpErlangString(testData[i]) };
                OtpErlangObject actual = conn.read(
                        new OtpErlangString(testTime + key + i));
                OtpErlangTuple expected = new OtpErlangTuple(data);
                assertEquals(expected, actual);
            }
        } finally {
            conn.closeConnection();
        }
    }
    
    /**
     * Test method for
     * {@link TransactionSingleOp#testAndSet(OtpErlangString, OtpErlangObject, OtpErlangObject)},
     * {@link TransactionSingleOp#read(OtpErlangString)}
     * and {@link TransactionSingleOp#write(OtpErlangString, OtpErlangObject)}.
     * Writes an erlang tuple and tries to overwrite it using test_and_set
     * knowing the wrong old value. Tries to read the data afterwards.
     * 
     * @throws UnknownException
     * @throws TimeoutException
     * @throws ConnectionException
     * @throws NotFoundException 
     * @throws AbortException 
     * 
     * @since 2.7
     */
    @Test
    public void testTestAndSetOtp2() throws ConnectionException,
            TimeoutException, UnknownException, NotFoundException, AbortException {
        String key = "_TestAndSetOtp2";
        TransactionSingleOp conn = new TransactionSingleOp();

        try {
            // first write all values:
            for (int i = 0; i < testData.length - 1; i += 2) {
                OtpErlangObject[] data = new OtpErlangObject[] {
                        new OtpErlangString(testData[i]),
                        new OtpErlangString(testData[i + 1]) };
                conn.write(
                        new OtpErlangString(testTime + key + i),
                        new OtpErlangTuple(data));
            }
            
            // now try to overwrite them using test_and_set:
            for (int i = 0; i < testData.length - 1; i += 2) {
                OtpErlangObject[] old_data = new OtpErlangObject[] {
                        new OtpErlangString(testData[i]),
                        new OtpErlangString(testData[i]) };
                OtpErlangObject new_value = CommonErlangObjects.failAtom;
                try {
                    conn.testAndSet(
                            new OtpErlangString(testTime + key + i),
                            new OtpErlangTuple(old_data), new_value);
                    // a key changed exception must be thrown
                    assertTrue(false);
                } catch (KeyChangedException e) {
                    OtpErlangObject[] data = new OtpErlangObject[] {
                            new OtpErlangString(testData[i]),
                            new OtpErlangString(testData[i + 1]) };
                    OtpErlangTuple expected = new OtpErlangTuple(data);
                    assertEquals(expected, e.getOldValue());
                }
            }
            
            // now try to read the data:
            for (int i = 0; i < testData.length - 1; i += 2) {
                OtpErlangObject[] data = new OtpErlangObject[] {
                        new OtpErlangString(testData[i]),
                        new OtpErlangString(testData[i + 1]) };
                OtpErlangObject actual = conn.read(
                        new OtpErlangString(testTime + key + i));
                OtpErlangTuple expected = new OtpErlangTuple(data);
                assertEquals(expected, actual);
            }
        } finally {
            conn.closeConnection();
        }
    }

    /**
     * Test method for
     * {@link TransactionSingleOp#testAndSet(String, String, String)}
     * with a closed connection.
     * 
     * @throws UnknownException
     * @throws TimeoutException
     * @throws ConnectionException
     * @throws NotFoundException
     * @throws AbortException 
     * @throws KeyChangedException 
     * 
     * @since 2.7
     */
    @Test(expected=ConnectionException.class)
    public void testTestAndSet_NotConnected() throws ConnectionException,
            TimeoutException, UnknownException, NotFoundException, AbortException, KeyChangedException {
        String key = "_TestAndSet_NotConnected";
        TransactionSingleOp conn = new TransactionSingleOp();
        conn.closeConnection();
        conn.testAndSet(testTime + key, testData[0], testData[1]);
    }
    
    /**
     * Test method for
     * {@link TransactionSingleOp#testAndSet(String, String, String)}.
     * Tries test_and_set with a non-existing key.
     * 
     * @throws UnknownException
     * @throws TimeoutException
     * @throws ConnectionException
     * @throws NotFoundException 
     * @throws AbortException 
     * @throws KeyChangedException 
     * 
     * @since 2.7
     */
    @Test(expected=NotFoundException.class)
    public void testTestAndSet_NotFound() throws ConnectionException,
            TimeoutException, UnknownException, NotFoundException, AbortException, KeyChangedException {
        String key = "_TestAndSet_NotFound";
        TransactionSingleOp conn = new TransactionSingleOp();

        try {
            conn.testAndSet(testTime + key, testData[0], testData[1]);
        } finally {
            conn.closeConnection();
        }
    }
    
    /**
     * Test method for
     * {@link TransactionSingleOp#testAndSet(String, String, String)},
     * {@link TransactionSingleOp#read(String)}
     * and {@link TransactionSingleOp#write(String, String)}.
     * Writes a string and tries to overwrite it using test_and_set
     * knowing the correct old value. Tries to read the string afterwards.
     * 
     * @throws UnknownException
     * @throws TimeoutException
     * @throws ConnectionException
     * @throws NotFoundException 
     * @throws AbortException 
     * @throws KeyChangedException 
     * 
     * @since 2.7
     */
    @Test
    public void testTestAndSet1() throws ConnectionException,
            TimeoutException, UnknownException, NotFoundException, AbortException, KeyChangedException {
        String key = "_TestAndSet1";
        TransactionSingleOp conn = new TransactionSingleOp();

        try {
            // first write all values:
            for (int i = 0; i < testData.length - 1; i += 2) {
                conn.write(testTime + key + i, testData[i]);
            }
            
            // now try to overwrite them using test_and_set:
            for (int i = 0; i < testData.length - 1; i += 2) {
                conn.testAndSet(testTime + key + i, testData[i], testData[i + 1]);
            }
            
            // now try to read the data:
            for (int i = 0; i < testData.length - 1; i += 2) {
                assertEquals(testData[i + 1], conn.read(testTime + key + i).toString());
            }
        } finally {
            conn.closeConnection();
        }
    }
    
    /**
     * Test method for
     * {@link TransactionSingleOp#testAndSet(String, String, String)},
     * {@link TransactionSingleOp#read(String)}
     * and {@link TransactionSingleOp#write(String, String)}.
     * Writes a string and tries to overwrite it using test_and_set
     * knowing the wrong old value. Tries to read the string afterwards.
     * 
     * @throws UnknownException
     * @throws TimeoutException
     * @throws ConnectionException
     * @throws NotFoundException 
     * @throws AbortException 
     * 
     * @since 2.7
     */
    @Test
    public void testTestAndSet2() throws ConnectionException,
            TimeoutException, UnknownException, NotFoundException, AbortException {
        String key = "_TestAndSet2";
        TransactionSingleOp conn = new TransactionSingleOp();

        try {
            // first write all values:
            for (int i = 0; i < testData.length - 1; i += 2) {
                conn.write(testTime + key + i, testData[i]);
            }
            
            // now try to overwrite them using test_and_set:
            for (int i = 0; i < testData.length - 1; i += 2) {
                try {
                    conn.testAndSet(testTime + key + i, testData[i + 1], "fail");
                    // a key changed exception must be thrown
                    assertTrue(false);
                } catch (KeyChangedException e) {
                    OtpErlangString expected = new OtpErlangString(testData[i]);
                    assertEquals(expected, e.getOldValue());
                }
            }
            
            // now try to read the data:
            for (int i = 0; i < testData.length - 1; i += 2) {
                assertEquals(testData[i], conn.read(testTime + key + i).toString());
            }
        } finally {
            conn.closeConnection();
        }
    }
}
