const express = require('express');
const mysql = require('mysql');
const bodyParser = require('body-parser');
const nodemailer = require('nodemailer');
const https = require('https');
const fs = require('fs');
const app = express();
const privateKey = fs.readFileSync('/etc/letsencrypt/live/apps.plestarinc.com/privkey.pem', 'utf8');
const certificate = fs.readFileSync('/etc/letsencrypt/live/apps.plestarinc.com/fullchain.pem', 'utf8');
const credentials = { key: privateKey, cert: certificate };
const multer = require('multer');
const path = require('path');
const { v4: uuidv4 } = require('uuid');
const httpsServer = https.createServer(credentials, app);
app.use(bodyParser.json({ limit: '10mb' }));
app.use(bodyParser.urlencoded({ limit: '10mb', extended: true }));
app.use((req, res, next) => {
    res.header('Access-Control-Allow-Origin', 'https://apps.plestarinc.com');
    res.header('Access-Control-Allow-Methods', 'POST');
    res.header('Access-Control-Allow-Headers', 'Content-Type');
    next();
});
const httpsPort = 3002;
httpsServer.listen(httpsPort, () => {
    console.log(`Server is running on https://apps.plestarinc.com:${httpsPort}`);
});
/*async function connectToMongoDB() {
  const uri = 'mongodb://localhost:27017';
  const client = new MongoClient(uri);
  try {
    await client.connect();
    console.log('Connected to MongoDB');

    const db = client.db('eContacts'); 
    const contactsCollection = db.collection('contacts');
    const storage = multer.memoryStorage();
    const upload = multer({ storage: storage });

    app.post('/savecontactss', async (req, res) => {
        const { name, phone, service, location, location1, imagebolb, filename, about, keyword } = req.body;
        let imageBuffer = null;
        const uniqueFilename = filename;

        if (imagebolb && imagebolb.length > 0) {
            imageBuffer = Buffer.from(imagebolb, 'base64');
        }

        try {
            const existingContact = await contactsCollection.findOne({ phone_no: phone });

            if (existingContact) {
                const updateResult = await contactsCollection.updateOne(
                    { phone_no: phone },
                    {
                        $set: {
                            name,
                            service,
                            location,
                            location1,
                            image: uniqueFilename,
                            about,
                            keywords: keyword,
                        },
                    }
                );
 
                console.log('Phone number updated successfully');
                res.status(200).send('Phone number saved successfully');

                if (imageBuffer) {
                    const imagePath = path.join(__dirname, 'uploads', uniqueFilename);
                    fs.writeFile(imagePath, imageBuffer, 'base64', (err) => {
                        if (err) {
                            console.error(err);
                        } else {
                            console.log('Image saved successfully');
                        }
                    });
                }
            } else {
                const insertResult = await contactsCollection.insertOne({
                    name,
                    phone_no: phone,
                    service,
                    location,
                    location1,
                    image: uniqueFilename,
                    keywords: keyword,
                    about,
                });

                console.log('Phone number saved successfully');
                res.status(200).send('Phone number saved successfully');

                if (imageBuffer) {
                    const imagePath = path.join(__dirname, 'uploads', uniqueFilename);
                    fs.writeFile(imagePath, imageBuffer, 'base64', (err) => {
                        if (err) {
                            console.error(err);
                        } else {
                            console.log('Image saved successfully');
                        }
                    });
                }
            }
        } catch (error) {
            console.error('Error processing request:', error);
            res.status(500).send('Error processing request');
        }
    });
app.get('/check-contacts', async (req, res) => {
    const type = req.query.type;
    const location = req.query.location;

    try {
        let pipeline;

        if (type === "nearme") {
            pipeline = [
                {
                    $match: {
                        $or: [
                            { priority: 0, priority_balance: { $gte: 25 }, location: { $regex: new RegExp(location, 'i') } },
                            { location: { $regex: new RegExp(location, 'i') } }
                        ]
                    }
                },
                { $sample: { size: 3 } }
            ];
        } else {
            pipeline = [
                {
                    $match: {
                        priority: 0,
                        priority_balance: { $gte: 25 }
                    }
                },
                { $sample: { size: 3 } }
            ];
        }

        const checkPhoneResult = await db.collection('contacts').aggregate(pipeline).toArray();

        if (checkPhoneResult.length > 0) {
            res.status(200).json(checkPhoneResult);
        } else {
            res.status(200).json([{ status: 'No data' }]);
        }
    } catch (error) {
        console.error('Error checking phone number:', error);
        res.status(500).send('Internal Server Error');
    }
});



  } catch (err) {
    console.error('Error connecting to MongoDB:', err.message);
  } 
}

connectToMongoDB();*/
const db = mysql.createConnection({
    host: 'localhost',
    user: 'root',
    password: 'Plestar@7542',
    database: 'tpdirectory',
});

db.connect((err) => {
    if (err) {
        console.error('Error connecting to MySQL:', err.message);
        return;
    }
    console.log('Connected to MySQL');
});
const storage = multer.memoryStorage();
const upload = multer({ storage: storage });
app.post('/savecontacts', (req, res) => {
    var { id, name, phone, phone1, email, service, location, location1, state, city, imagebolb, filename, about, keyword, landlineno, wpno, skypeno, category, output, services, publish, owner_email } = req.body;
    if (services == null) {
        services = "";
    }
    if (phone1 == null || phone1 == "") {
        phone1 = phone;
    }
    let imageBuffer = null;
    const sanitize = (str) => str.replace(/\s+/g, '_').replace(/[^a-zA-Z0-9_]/g, '');
    const safeName = sanitize(name || 'user');
    const safePhone = sanitize(phone || 'unknown');
    var uniqueFilename = "";
    if (imagebolb && imagebolb.length > 0) {
        const fileSuffix = id ? `_${id}` : `_${Date.now()}`;
        uniqueFilename = `${safeName}_${safePhone}${fileSuffix}.jpg`;
        imageBuffer = Buffer.from(imagebolb, 'base64');
    }

    if (id) {
        // Update specific profile by ID
        const checkSql = "SELECT * FROM contacts WHERE id = ?";
        db.query(checkSql, [id], (selectErr, selectResult) => {
            if (selectErr) {
                console.error(selectErr);
                return res.status(500).send('Error checking profile ID');
            }
            if (selectResult.length > 0) {
                const finalImage = uniqueFilename || selectResult[0].image || '';
                var updateQuery = "UPDATE contacts SET name = ?, phone_no = ?, service = ?, email = ?, location = ?, location1 = ?, state = ?, city = ?, image = ?, about = ?, keywords = ?, landlineno = ?, wpno = ?, skypeno = ?, category = ?, phonenos = ?, owner_email = ?, services = ?, deleted_contact = 0 WHERE id = ?";
                var updateValues = [name, phone, service, email, location, location1, state, city, finalImage, about, keyword, landlineno, wpno, skypeno, category, output, owner_email, services, id];

                db.query(updateQuery, updateValues, (updateErr, updateResult) => {
                    if (updateErr) {
                        console.error(updateErr);
                        return res.status(500).send('Error updating profile');
                    }
                    console.log(`Business profile ${id} updated successfully`);
                    res.status(200).json({ status: 'success', id: id, message: 'Phone number saved successfully' });
                    if (imageBuffer != null && uniqueFilename) {
                        const imagePath = path.join(__dirname, 'uploads', uniqueFilename);
                        fs.writeFile(imagePath, imageBuffer, 'base64', (err) => {
                            if (err) console.error(err);
                            else console.log('Image saved successfully');
                        });
                    }
                });
            } else {
                // ID provided but not found, insert as new profile
                const insertQuery = "INSERT INTO contacts (name, phone_no, email, service, location, location1, state, city, image, keywords, about, landlineno, wpno, skypeno, category, phonenos, publish, owner_email, services) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)";
                const insertValues = [name, phone, email, service, location, location1, state, city, uniqueFilename, keyword, about, landlineno, wpno, skypeno, category, output, publish || 'yes', owner_email, services];

                db.query(insertQuery, insertValues, (insertErr, insertResult) => {
                    if (insertErr) {
                        console.error(insertErr);
                        return res.status(500).send('Error creating profile');
                    }
                    console.log(`New profile created with ID ${insertResult.insertId}`);
                    res.status(200).json({ status: 'success', id: insertResult.insertId, message: 'Phone number saved successfully' });
                    if (imageBuffer != null && uniqueFilename) {
                        const imagePath = path.join(__dirname, 'uploads', uniqueFilename);
                        fs.writeFile(imagePath, imageBuffer, 'base64', (err) => {
                            if (err) console.error(err);
                        });
                    }
                });
            }
        });
    } else {
        // Fallback: If no ID provided
        const selectQuery = "SELECT * FROM contacts WHERE phone_no = ? AND deleted_contact = 0";
        db.query(selectQuery, [phone1], (selectErr, selectResult) => {
            if (selectErr) {
                console.error(selectErr);
                return res.status(500).send('Error checking phone number');
            }
            if (selectResult.length > 0) {
                const targetId = selectResult[0].id;
                const finalImage = uniqueFilename || selectResult[0].image || '';
                var updateQuery = "UPDATE contacts SET name = ?, phone_no = ?, service = ?, email = ?, location = ?, location1 = ?, state = ?, city = ?, image = ?, about = ?, keywords = ?, landlineno = ?, wpno = ?, skypeno = ?, category = ?, phonenos = ?, owner_email = ?, services = ?, deleted_contact = 0 WHERE id = ?";
                var updateValues = [name, phone, service, email, location, location1, state, city, finalImage, about, keyword, landlineno, wpno, skypeno, category, output, owner_email, services, targetId];

                db.query(updateQuery, updateValues, (updateErr, updateResult) => {
                    if (updateErr) {
                        console.error(updateErr);
                        return res.status(500).send('Error updating profile');
                    }
                    res.status(200).json({ status: 'success', id: targetId, message: 'Phone number saved successfully' });
                    if (imageBuffer != null && uniqueFilename) {
                        const imagePath = path.join(__dirname, 'uploads', uniqueFilename);
                        fs.writeFile(imagePath, imageBuffer, 'base64', (err) => {
                            if (err) console.error(err);
                        });
                    }
                });
            } else {
                const insertQuery = "INSERT INTO contacts (name, phone_no, email, service, location, location1, state, city, image, keywords, about, landlineno, wpno, skypeno, category, phonenos, publish, owner_email, services) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)";
                const insertValues = [name, phone, email, service, location, location1, state, city, uniqueFilename, keyword, about, landlineno, wpno, skypeno, category, output, publish || 'yes', owner_email, services];

                db.query(insertQuery, insertValues, (insertErr, insertResult) => {
                    if (insertErr) {
                        console.error(insertErr);
                        return res.status(500).send('Error submitting report');
                    }
                    res.status(200).json({ status: 'success', id: insertResult.insertId, message: 'Phone number saved successfully' });
                    if (imageBuffer != null && uniqueFilename) {
                        const imagePath = path.join(__dirname, 'uploads', uniqueFilename);
                        fs.writeFile(imagePath, imageBuffer, 'base64', (err) => {
                            if (err) console.error(err);
                        });
                    }
                });
            }
        });
    }
});
app.post('/receiveData', (req, res) => {
    const receivedData = Object.values(req.body.data);
    const email = req.body.email;
    let hasError = false;

    function insertOrUpdateContact(row) {
        if (hasError) {
            return;
        }
        const phone = row[0] + row[1];
        const name = row[2];
        const service = row[3];
        const country = row[4];
        const state = row[5];
        const city = row[6];
        const location = `${city}, ${state}, ${country}`;
        const location1 = `${city}, ${state}`;
        const keywords = service;
        const owner_email = email;

        const prevQuery = 'SELECT * FROM contacts WHERE phone_no = ?';
        db.query(prevQuery, [phone], (err, results) => {
            if (err) {
                console.error('Error querying database:', err);
                hasError = true;
                res.status(500).json({ status: 'Error querying database' });
                return;
            }

            const c = results.length;

            if (c > 0) {
                const updateQuery = 'UPDATE contacts SET name = ?, wpno = ?, service = ?, location = ?, location1 = ?, state = ?, city = ?, keywords = ?, owner_email = ? WHERE phone_no = ?';
                const updateValues = [name, phone, service, location, location1, state, city, keywords, owner_email, phone];

                db.query(updateQuery, updateValues, (err) => {
                    if (err) {
                        console.error('Error updating contact:', err);
                        hasError = true;
                        res.status(500).json({ status: 'Error updating contact' });
                    }
                });
            } else {
                const insertQuery = 'INSERT INTO contacts (name, phone_no, wpno, service, location, location1, state, city, keywords, category, owner_email) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, "Government", ?)';
                const insertValues = [name, phone, phone, service, location, location1, state, city, keywords, owner_email];

                db.query(insertQuery, insertValues, (err) => {
                    if (err) {
                        console.error('Error inserting contact:', err);
                        hasError = true;
                        res.status(500).json({ status: 'Error inserting contact' });
                    }
                });
            }
        });
    }
    for (const row of receivedData) {
        insertOrUpdateContact(row);
    }
    if (!hasError) {
        res.json({ status: 'All contacts processed successfully' });
    }
});

app.post('/savecontacts1', (req, res) => {
    var { id, name, phone, email, service, location, location1, state, city, imagebolb, filename, about, keyword, landlineno, wpno, skypeno, category, output, services, publish, owner_email } = req.body;
    if (services == null) {
        services = "";
    }
    let imageBuffer = null;
    const sanitize = (str) => str.replace(/\s+/g, '_').replace(/[^a-zA-Z0-9_]/g, '');
    const safeName = sanitize(name || 'user');
    const safePhone = sanitize(phone || 'unknown');
    var uniqueFilename = "";
    if (imagebolb && imagebolb.length > 0) {
        const fileSuffix = id ? `_${id}` : `_${Date.now()}`;
        uniqueFilename = `${safeName}_${safePhone}${fileSuffix}.jpg`;
        imageBuffer = Buffer.from(imagebolb, 'base64');
    }

    if (id) {
        // If ID passed, update that specific profile
        const checkSql = "SELECT * FROM contacts WHERE id = ?";
        db.query(checkSql, [id], (checkErr, checkResult) => {
            if (checkErr) return res.status(500).send('Error checking contact');
            if (checkResult.length > 0) {
                const finalImage = uniqueFilename || checkResult[0].image || '';
                var updateQuery = "UPDATE contacts SET name = ?, phone_no = ?, service = ?, email = ?, location = ?, location1 = ?, state = ?, city = ?, image = ?, about = ?, keywords = ?, landlineno = ?, wpno = ?, skypeno = ?, category = ?, phonenos = ?, owner_email = ?, services = ?, deleted_contact = 0 WHERE id = ?";
                var updateValues = [name, phone, service, email, location, location1, state, city, finalImage, about, keyword, landlineno, wpno, skypeno, category, output, owner_email, services, id];

                db.query(updateQuery, updateValues, (updateErr) => {
                    if (updateErr) return res.status(500).send('Error updating profile');
                    res.status(200).json({ status: 'success', id: id, message: 'Phone number saved successfully' });
                    if (imageBuffer != null && uniqueFilename) {
                        const imagePath = path.join(__dirname, 'uploads', uniqueFilename);
                        fs.writeFile(imagePath, imageBuffer, 'base64', (err) => { if (err) console.error(err); });
                    }
                });
            } else {
                // Insert as new
                const insertQuery = "INSERT INTO contacts (name, phone_no, email, service, location, location1, state, city, image, keywords, about, landlineno, wpno, skypeno, category, phonenos, publish, owner_email, services) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)";
                const insertValues = [name, phone, email, service, location, location1, state, city, uniqueFilename, keyword, about, landlineno, wpno, skypeno, category, output, publish || 'yes', owner_email, services];

                db.query(insertQuery, insertValues, (insertErr, insertResult) => {
                    if (insertErr) return res.status(500).send('Error creating profile');
                    res.status(200).json({ status: 'success', id: insertResult.insertId, message: 'Phone number saved successfully' });
                    if (imageBuffer != null && uniqueFilename) {
                        const imagePath = path.join(__dirname, 'uploads', uniqueFilename);
                        fs.writeFile(imagePath, imageBuffer, 'base64', (err) => { if (err) console.error(err); });
                    }
                });
            }
        });
    } else if (name != null && name.trim() !== '') {
        // ALWAYS INSERT a new profile when creating a profile (allows multiple profiles with same phone number)
        const insertQuery = "INSERT INTO contacts (name, phone_no, email, service, location, location1, state, city, image, keywords, about, landlineno, wpno, skypeno, category, phonenos, publish, owner_email, services) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)";
        const insertValues = [name, phone, email, service, location, location1, state, city, uniqueFilename, keyword, about, landlineno, wpno, skypeno, category, output, publish || 'yes', owner_email, services];

        db.query(insertQuery, insertValues, (insertErr, insertResult) => {
            if (insertErr) {
                console.error(insertErr);
                return res.status(500).send('Error submitting report');
            }
            console.log(`Phone number saved successfully with new ID: ${insertResult.insertId}`);
            res.status(200).json({ status: 'success', id: insertResult.insertId, message: 'Phone number saved successfully' });
            if (imageBuffer != null && uniqueFilename) {
                const imagePath = path.join(__dirname, 'uploads', uniqueFilename);
                fs.writeFile(imagePath, imageBuffer, 'base64', (err) => {
                    if (err) console.error(err);
                });
            }
        });
    } else {
        // Quick publish/email update
        if (id) {
            var updateQuery = "UPDATE contacts SET email=?, publish=? WHERE id = ?";
            db.query(updateQuery, [email, publish, id], (updateErr) => {
                if (updateErr) return res.status(500).send('Error updating profile');
                res.status(200).send('Phone number saved successfully');
            });
        } else {
            var updateQuery = "UPDATE contacts SET email=?, publish=? WHERE phone_no = ?";
            db.query(updateQuery, [email, publish, phone], (updateErr) => {
                if (updateErr) return res.status(500).send('Error updating phone number');
                res.status(200).send('Phone number saved successfully');
            });
        }
    }
});

app.get('/check-contact', async (req, res) => {
    const type = req.query.type || "all";
    const location = req.query.location || "";
    const query = req.query.query || "";
    const trimmedQuery = query.toLowerCase().trim();


    if (type === "search") {
        if (!trimmedQuery) return res.status(200).json([]);

        const searchPattern = `%${trimmedQuery}%`;

        // For Phrase Search: We create a regex that checks if the field contains all words
        // If query is "Best Plumber", regex becomes "Best.*Plumber|Plumber.*Best"
        const words = trimmedQuery.split(/\s+/);
        const phraseRegex = words.join('.*');

        var checkPhoneSql = `
            /* 1. Top 3 Random Ads */
            (SELECT * FROM contacts 
             WHERE priority=0 AND priority_balance>=0.30 AND publish='yes' AND deleted_contact=0
             AND (name LIKE ? OR keywords LIKE ? OR location LIKE ? OR service LIKE ?)
             ORDER BY Rand() LIMIT 3)
            
            UNION
            
            /* 2. Main Filtered Results based on search_type */
            (SELECT * FROM contacts 
             WHERE publish='yes' AND deleted_contact=0 
             AND (
                /* BROAD LOGIC */
                (search_type = 'broad' AND (name LIKE ? OR keywords LIKE ? OR location LIKE ?))
                
                OR
                
                /* EXACT LOGIC */
                /* FIND_IN_SET checks comma separated strings, REPLACE handles the space after comma */
                (search_type = 'exact' AND (FIND_IN_SET(?, REPLACE(keywords, ', ', ',')) > 0 OR service = ?))
                
                OR
                
                /* PHRASE LOGIC */
                /* Checks if the keywords column matches the word sequence */
                (search_type LIKE '%phrase%' AND (keywords REGEXP ?))
             )`;

        var value = [
            searchPattern, searchPattern, searchPattern, searchPattern, // For Ads
            searchPattern, searchPattern, searchPattern, trimmedQuery, trimmedQuery, phraseRegex // For Results
        ];
        if (location !== "") {
            const locationArray = location.split(', ');
            const lastElement = locationArray[locationArray.length - 1];

            checkPhoneSql += ` AND location LIKE ?`;
            value.push(`%${lastElement}%`);
        }

        checkPhoneSql += ` ORDER BY priority_balance DESC);`;

    } else if (type == "nearme") {
        var checkPhoneSql = "(SELECT * FROM contacts WHERE priority=0 and priority_balance>=0.30 AND publish='yes' and deleted_contact=0 and promote_country=? ORDER BY Rand() limit 3) UNION (SELECT * FROM (SELECT * FROM contacts where location LIKE Concat('%',?,'%') AND publish='yes' and deleted_contact=0 GROUP BY id ORDER BY id DESC) AS subquery);";
        var value = [location, location];
    } else if (type == "location") {
        var locationArray = location.split(', ');
        var lastElement = locationArray[locationArray.length - 1];
        var checkPhoneSql = "(SELECT * FROM contacts WHERE priority=0 and priority_balance>=0.30 AND publish='yes' and deleted_contact=0 and (promote_city='All' or ? like CONCAT('%', promote_city, '%')) ORDER BY Rand() limit 3) UNION (SELECT * FROM (SELECT * FROM contacts where location LIKE Concat('%',?,'%') AND publish='yes' and deleted_contact=0 GROUP BY id ORDER BY id DESC) AS subquery);";
        var value = [lastElement, lastElement];
    } else if (type == "all") {
        var checkPhoneSql = `(SELECT * FROM contacts WHERE priority=0 and priority_balance>=0.30 AND publish="yes" and deleted_contact=0 and promote_international="yes" ORDER BY Rand() limit 3) UNION (SELECT * FROM (SELECT * FROM contacts WHERE publish="yes" and deleted_contact=0 GROUP BY id ORDER BY id DESC) AS subquery);`;
        var value = [];
    } else {
        var checkPhoneSql = `(SELECT * FROM contacts WHERE priority=0 and priority_balance>=0.30 AND publish="yes" and deleted_contact=0 and promote_international="yes" ORDER BY Rand() limit 3) UNION (SELECT * FROM (SELECT * FROM contacts WHERE publish="yes" and deleted_contact=0 GROUP BY id ORDER BY id DESC limit 200) AS subquery);`;
        var value = [];
    }
    db.query(checkPhoneSql, value, (checkPhoneErr, checkPhoneResult) => {
        if (checkPhoneErr) {
            console.error('Error checking phone number:', checkPhoneErr);
            console.error('SQL Query:', checkPhoneSql);
            console.error('SQL Values:', value);
            res.status(200).send('Error checking phone number');
            return;
        }
        if (checkPhoneResult.length > 0) {
            res.status(200).json(checkPhoneResult);
        } else {
            res.status(200).json([{ status: 'No data' }]);
        }
    });
});
app.post('/delete_contact', (req, res) => {
    const { id, phone } = req.body;

    if (id) {
        var updateQuery = "UPDATE contacts SET deleted_contact=1, publish='no' WHERE id = ?";
        var updateValues = [id];

        db.query(updateQuery, updateValues, (updateErr, updateResult) => {
            if (updateErr) {
                console.error(updateErr);
                res.status(500).send('Error deleting profile');
            } else {
                console.log(`Profile ${id} deleted`);
                res.status(200).send('phone no deleted');
            }
        });
    } else {
        var updateQuery = "UPDATE contacts SET deleted_contact=1, publish='no' WHERE phone_no = ?";
        var updateValues = [phone];

        db.query(updateQuery, updateValues, (updateErr, updateResult) => {
            if (updateErr) {
                console.error(updateErr);
                res.status(500).send('Error updating call count');
            } else {
                console.log('Phone no deleted');
                res.status(200).send('phone no deleted');
            }
        });
    }
});
app.post('/savetags', (req, res) => {
    const { id, tags, phone } = req.body;

    if (id) {
        var updateQuery = "UPDATE contacts SET keywords=? WHERE id = ?";
        var updateValues = [tags, id];

        db.query(updateQuery, updateValues, (updateErr, updateResult) => {
            if (updateErr) {
                console.error(updateErr);
                res.status(500).send('Error updating keywords');
            } else {
                console.log(`Keywords updated for profile ${id}`);
                res.status(200).send('Phone number saved successfully');
            }
        });
    } else {
        var updateQuery = "UPDATE contacts SET keywords=? WHERE phone_no = ?";
        var updateValues = [tags, phone];

        db.query(updateQuery, updateValues, (updateErr, updateResult) => {
            if (updateErr) {
                console.error(updateErr);
                res.status(500).send('Error updating phone number');
            } else {
                console.log('Phone number updated successfully');
                res.status(200).send('Phone number saved successfully');
            }
        });
    }
});
app.post('/savesearch', (req, res) => {
    const { tag, location, country } = req.body;
    var updateQuery = "INSERT INTO `search_tags` (`tags`,location,country) VALUES (?,?,?);";
    var updateValues = [tag, location, country];

    db.query(updateQuery, updateValues, (updateErr, updateResult) => {
        if (updateErr) {
            console.error(updateErr);
            res.status(500).send('Error updating phone number');
        } else {
            console.log('Tag Saved');
            res.status(200).send('Tag saved');
        }
    });
});
app.get('/check-search', (req, res) => {
    var tags = req.query.tags;
    if (tags != null) {
        tags = tags.trim();
        var words = tags.split(/\s*,\s*/);
    }
    var type = req.query.type;
    var checkPhoneSql = "SELECT tags,count(*) as count FROM search_tags WHERE ";
    var conditions = [];
    var value = [];

    for (var i = 0; i < words.length; i++) {
        conditions.push("tags LIKE ?");
        value.push("%" + words[i] + "%");
    }

    if (conditions.length > 0) {
        checkPhoneSql += "(" + conditions.join(" OR ") + ")";
    } else {
        checkPhoneSql += "1";
    }
    if (type == "All" || type == null) {
        checkPhoneSql += ``;
    } else if (type == "Today") {
        checkPhoneSql += ` AND DATE(created) = CURDATE() `;
    } else if (type == "Yesterday") {
        checkPhoneSql += ` AND DATE(created) = CURDATE() - INTERVAL 1 DAY `;
    } else if (type == "Last 7 days") {
        checkPhoneSql += ` AND created >= CURDATE() - INTERVAL 7 DAY `;
    } else if (type == "Last Week") {
        checkPhoneSql += ` AND created >= CURDATE() - INTERVAL 1 WEEK AND created < CURDATE() `;
    } else if (type == "Last Month") {
        checkPhoneSql += ` AND created >= DATE_FORMAT(CURDATE() - INTERVAL 1 MONTH, '%Y-%m-01') AND created < DATE_FORMAT(CURDATE(), '%Y-%m-01') `;
    }
    checkPhoneSql += " Group BY tags ORDER BY Max(id) DESC;";
    db.query(checkPhoneSql, value, (checkPhoneErr, checkPhoneResult) => {
        if (checkPhoneErr) {
            console.error('Error checking phone number:', checkPhoneErr);
            res.status(200).send('Error checking phone number');
            return;
        }
        if (checkPhoneResult.length > 0) {
            res.status(200).json(checkPhoneResult);
        } else {
            res.status(200).json([{ error: 'No data' }]);
        }
    });
});
app.get('/check-search1', (req, res) => {
    var type = req.query.type;
    var checkPhoneSql = "SELECT tags,count(*) as count FROM search_tags WHERE ";
    var conditions = [];
    var value = [];
    if (type == "All" || type == null) {
        checkPhoneSql += `1`;
    } else if (type == "Today") {
        checkPhoneSql += ` DATE(created) = CURDATE() `;
    } else if (type == "Yesterday") {
        checkPhoneSql += ` DATE(created) = CURDATE() - INTERVAL 1 DAY `;
    } else if (type == "Last 7 days") {
        checkPhoneSql += ` created >= CURDATE() - INTERVAL 7 DAY `;
    } else if (type == "Last Week") {
        checkPhoneSql += ` created >= CURDATE() - INTERVAL 1 WEEK AND created < CURDATE() `;
    } else if (type == "Last Month") {
        checkPhoneSql += ` created >= DATE_FORMAT(CURDATE() - INTERVAL 1 MONTH, '%Y-%m-01') AND created < DATE_FORMAT(CURDATE(), '%Y-%m-01') `;
    }
    checkPhoneSql += " Group BY tags ORDER BY Max(id) DESC;";
    db.query(checkPhoneSql, value, (checkPhoneErr, checkPhoneResult) => {
        if (checkPhoneErr) {
            console.error('Error checking phone number:', checkPhoneErr);
            res.status(200).send('Error checking phone number');
            return;
        }
        if (checkPhoneResult.length > 0) {
            res.status(200).json(checkPhoneResult);
        } else {
            res.status(200).json([{ error: 'No data' }]);
        }
    });
});
app.get('/check-search2', (req, res) => {
    var tags = req.query.tags;
    var phone = req.query.phone;
    const phone1 = "%" + phone.replace(/\s+/g, '') + "%";
    if (tags != null) {
        tags = tags.trim();
        var words = tags.split(/\s*,\s*/);
    }
    var type = req.query.type;
    var checkPhoneSql = "SELECT search.tags, COALESCE(search_count, 0) AS search_count, COALESCE(call_count, 0) AS call_count FROM (SELECT tags,count(*) as search_count, max(id) as max_id FROM search_tags WHERE ";
    var conditions = [];
    var value = [];

    for (var i = 0; i < words.length; i++) {
        conditions.push("tags like ?");
        value.push("%" + words[i] + "%");
    }

    if (conditions.length > 0) {
        checkPhoneSql += "(" + conditions.join(" OR ") + ")";
    } else {
        checkPhoneSql += "1";
    }
    var condtionDate = "";
    if (type == "All" || type == null) {
        condtionDate = ``;
    } else if (type == "Today") {
        condtionDate = ` AND DATE(created) = CURDATE() `;
    } else if (type == "Yesterday") {
        condtionDate = ` AND DATE(created) = CURDATE() - INTERVAL 1 DAY `;
    } else if (type == "Last 7 days") {
        condtionDate = ` AND created >= CURDATE() - INTERVAL 7 DAY `;
    } else if (type == "Last Week") {
        condtionDate = ` AND created >= CURDATE() - INTERVAL 1 WEEK AND created < CURDATE() `;
    } else if (type == "Last Month") {
        condtionDate = ` AND created >= DATE_FORMAT(CURDATE() - INTERVAL 1 MONTH, '%Y-%m-01') AND created < DATE_FORMAT(CURDATE(), '%Y-%m-01') `;
    }
    checkPhoneSql += condtionDate + " Group BY tags) AS search LEFT JOIN (SELECT tag, COUNT(DISTINCT id) AS call_count FROM call_count WHERE phone_no=? " + condtionDate + " GROUP BY tag) AS call_counts ON search.tags = call_counts.tag ORDER BY search.max_id DESC";
    value.push(phone);
    db.query(checkPhoneSql, value, (checkPhoneErr, checkPhoneResult) => {
        if (checkPhoneErr) {
            console.error('Error checking phone number:', checkPhoneErr);
            res.status(200).send('Error checking phone number');
            return;
        }
        if (checkPhoneResult.length > 0) {
            res.status(200).json(checkPhoneResult);
        } else {
            res.status(200).json([{ error: 'No data' }]);
        }
    });
});
app.get('/check-search3', (req, res) => {
    var tags = req.query.tags;
    var phone = req.query.phone;
    const phone1 = "%" + phone.replace(/\s+/g, '') + "%";
    if (tags != null) {
        tags = tags.trim();
        var words = tags.split(/\s*,\s*/);
    }
    var type = req.query.type;
    var checkPhoneSql = "SELECT search.tags, COALESCE(search_count, 0) AS search_count, COALESCE(call_count, 0) AS call_count FROM (SELECT tags,count(*) as search_count, max(id) as max_id FROM search_tags WHERE ";
    var conditions = [];
    var value = [];

    for (var i = 0; i < words.length; i++) {
        conditions.push("tags like ?");
        value.push("%" + words[i] + "%");
    }

    if (conditions.length > 0) {
        checkPhoneSql += "(" + conditions.join(" OR ") + ")";
    } else {
        checkPhoneSql += "1";
    }
    var condtionDate = "";
    if (type == "All" || type == null) {
        condtionDate = ``;
    } else if (type == "Today") {
        condtionDate = ` AND DATE(created) = CURDATE() `;
    } else if (type == "Yesterday") {
        condtionDate = ` AND DATE(created) = CURDATE() - INTERVAL 1 DAY `;
    } else if (type == "Last 7 days") {
        condtionDate = ` AND created >= CURDATE() - INTERVAL 7 DAY `;
    } else if (type == "Last Week") {
        condtionDate = ` AND created >= CURDATE() - INTERVAL 1 WEEK AND created < CURDATE() `;
    } else if (type == "Last Month") {
        condtionDate = ` AND created >= DATE_FORMAT(CURDATE() - INTERVAL 1 MONTH, '%Y-%m-01') AND created < DATE_FORMAT(CURDATE(), '%Y-%m-01') `;
    }
    checkPhoneSql += condtionDate + " Group BY tags) AS search LEFT JOIN (SELECT tag, COUNT(DISTINCT id) AS call_count FROM call_count WHERE phone_no = ? " + condtionDate + " and call_type='paid' GROUP BY tag) AS call_counts ON search.tags = call_counts.tag ORDER BY search.max_id DESC";
    value.push(phone);
    db.query(checkPhoneSql, value, (checkPhoneErr, checkPhoneResult) => {
        if (checkPhoneErr) {
            console.error('Error checking phone number:', checkPhoneErr);
            res.status(200).send('Error checking phone number');
            return;
        }
        if (checkPhoneResult.length > 0) {
            res.status(200).json(checkPhoneResult);
        } else {
            res.status(200).json([{ error: 'No data' }]);
        }
    });
});
app.post('/savecallcount', (req, res) => {
    const { phone_no, location, tag, country } = req.body;
    var updateQuery = "INSERT INTO `call_count` (phone_no,location,tag,country,call_type) VALUES (?, ?, ?,?,?);";
    var updateValues = [phone_no, location, tag, country, "normal"];

    db.query(updateQuery, updateValues, (updateErr, updateResult) => {
        if (updateErr) {
            console.error(updateErr);
            res.status(500).send('Error updating call count');
        } else {
            console.log('Call count Saved');
            res.status(200).send('Call count saved');
        }
    });
});
app.post('/savecallcount1', (req, res) => {
    const { phone_no, location, tag, country } = req.body;
    var updateQuery = "INSERT INTO `call_count` (phone_no,location,tag,country,call_type) VALUES (?, ?, ?,?,?);";
    var updateValues = [phone_no, location, tag, country, "paid"];

    db.query(updateQuery, updateValues, (updateErr, updateResult) => {
        if (updateErr) {
            console.error(updateErr);
            res.status(500).send('Error updating call count');
        } else {
            console.log('Call count Saved');
            //res.status(200).send('Call count saved');
            const selectQuery = "SELECT * FROM `contacts` WHERE phone_no = ? AND priority = 0 AND priority_balance >= 0.30;";
            const selectValues = [phone_no];

            db.query(selectQuery, selectValues, (selectErr, selectResult) => {
                if (selectErr) {
                    console.error(selectErr);
                    res.status(500).send('Error checking priority balance');
                } else {
                    if (selectResult.length > 0) {
                        const updateQuery1 = "SELECT owner FROM contacts WHERE phone_no=?;";
                        const updateValues1 = [phone_no];

                        db.query(updateQuery1, updateValues1, (updateErr, updateResult) => {
                            if (updateErr) {
                                console.error(updateErr);
                                res.status(500).send('Error updating priority balance');
                            } else {
                                if (updateResult.length > 0) {
                                    const owner = updateResult[0].owner;
                                    const updateQuery2 = "UPDATE contacts SET priority_balance = priority_balance - 0.30 WHERE phone_no IN (?,?);";
                                    const updateValues2 = [phone_no, owner];

                                    db.query(updateQuery2, updateValues2, (updateErr, updateResult) => {
                                        if (updateErr) {
                                            console.error(updateErr);
                                            res.status(500).send('Error updating priority balance');
                                        } else {
                                            console.log('Priority balance Updated');
                                            res.status(200).send('Call count and Priority balance updated');
                                        }
                                    });
                                } else {
                                    res.status(200).send('Owner not found for the specified phone number.');
                                }
                            }
                        });
                    } else {
                        res.status(200).send('Call count saved, but priority balance not updated (conditions not met).');
                    }
                }
            });
        }
    });
});
app.post('/addfavourite', (req, res) => {
    const { id, phone_no, count } = req.body;
    var delta = count == "1" ? 1 : -1;
    var updateQuery = id
        ? "update contacts set favourite_count=GREATEST(0, favourite_count + ?) where id=?;"
        : "update contacts set favourite_count=GREATEST(0, favourite_count + ?) where phone_no=?;";
    var updateValues = [delta, id || phone_no];

    db.query(updateQuery, updateValues, (updateErr, updateResult) => {
        if (updateErr) {
            console.error(updateErr);
            res.status(500).send('Error updating favourite count');
        } else {
            console.log('Favourite Added');
            res.status(200).send('Favourite Added');
        }
    });
});
app.get('/check-call_count', (req, res) => {
    const phone = req.query.phone;
    const type = req.query.type;
    const phone1 = "%" + phone.replace(/\s+/g, '') + "%";
    if (type == "All" || type == null) {
        var checkPhoneSql = `SELECT  location,count(*) as count FROM call_count where phone_no like ? GROUP by location ORDER BY MAX(id) DESC`;
    } else if (type == "Today") {
        var checkPhoneSql = `SELECT  location,count(*) as count FROM call_count where phone_no like ? AND DATE(created) = CURDATE() GROUP by location ORDER BY MAX(id) DESC`;
    } else if (type == "Yesterday") {
        var checkPhoneSql = `SELECT  location,count(*) as count FROM call_count where phone_no like ? AND DATE(created) = CURDATE() - INTERVAL 1 DAY GROUP by location ORDER BY MAX(id) DESC`;
    } else if (type == "Last 7 days") {
        var checkPhoneSql = `SELECT  location,count(*) as count FROM call_count where phone_no like ? AND created >= CURDATE() - INTERVAL 7 DAY GROUP by location ORDER BY MAX(id) DESC`;
    } else if (type == "Last Week") {
        var checkPhoneSql = `SELECT  location,count(*) as count FROM call_count where phone_no like ? AND created >= CURDATE() - INTERVAL 1 WEEK AND created < CURDATE() GROUP by location ORDER BY MAX(id) DESC`;
    } else if (type == "Last Month") {
        var checkPhoneSql = `SELECT  location,count(*) as count FROM call_count where phone_no like ? AND created >= DATE_FORMAT(CURDATE() - INTERVAL 1 MONTH, '%Y-%m-01') AND created < DATE_FORMAT(CURDATE(), '%Y-%m-01') GROUP by location ORDER BY MAX(id) DESC`;
    }
    var value = [phone1];
    db.query(checkPhoneSql, value, (checkPhoneErr, checkPhoneResult) => {
        if (checkPhoneErr) {
            console.error('Error checking phone number:', checkPhoneErr);
            res.status(200).send('Error checking phone number');
            return;
        }
        if (checkPhoneResult.length > 0) {
            res.status(200).json(checkPhoneResult);
        } else {
            res.status(200).json([{ error: 'No data' }]);
        }
    });
});
app.get('/check-call-count1', (req, res) => {
    var phone = req.query.phone;
    var call_type = req.query.call_type;
    var type = req.query.type;
    if (type == "All" || type == null) {
        var checkPhoneSql = `SELECT tag, COUNT(*) AS call_count FROM call_count WHERE phone_no like concat("%",?,"%") AND call_type = ? AND tag='' GROUP BY COALESCE(tag, 'Empty'), tag ORDER BY tag IS NULL, tag DESC;`;
    } else if (type == "Today") {
        var checkPhoneSql = `SELECT tag, COUNT(*) AS call_count FROM call_count WHERE phone_no like concat("%",?,"%") AND call_type = ? AND DATE(created) = CURDATE() AND tag='' GROUP BY COALESCE(tag, 'Empty'), tag ORDER BY tag IS NULL, tag DESC;`;
    } else if (type == "Yesterday") {
        var checkPhoneSql = `SELECT tag, COUNT(*) AS call_count FROM call_count WHERE phone_no like concat("%",?,"%") AND call_type = ? AND tag=''  AND DATE(created) = CURDATE() - INTERVAL 1 DAY GROUP BY COALESCE(tag, 'Empty'), tag ORDER BY tag IS NULL, tag DESC;`;
    } else if (type == "Last 7 days") {
        var checkPhoneSql = `SELECT tag, COUNT(*) AS call_count FROM call_count WHERE phone_no like concat("%",?,"%") AND call_type = ? AND tag='' AND created >= CURDATE() - INTERVAL 7 DAY GROUP BY COALESCE(tag, 'Empty'), tag ORDER BY tag IS NULL, tag DESC;`;
    } else if (type == "Last Week") {
        var checkPhoneSql = `SELECT tag, COUNT(*) AS call_count FROM call_count WHERE phone_no like concat("%",?,"%") AND call_type = ? AND tag='' AND created >= CURDATE() - INTERVAL 1 WEEK AND created < CURDATE() GROUP BY COALESCE(tag, 'Empty'), tag ORDER BY tag IS NULL, tag DESC;`;
    } else if (type == "Last Month") {
        var checkPhoneSql = `SELECT tag, COUNT(*) AS call_count FROM call_count WHERE phone_no like concat("%",?,"%") AND call_type = ? AND tag='' AND created >= DATE_FORMAT(CURDATE() - INTERVAL 1 MONTH, '%Y-%m-01') AND created < DATE_FORMAT(CURDATE(), '%Y-%m-01') GROUP BY COALESCE(tag, 'Empty'), tag ORDER BY tag IS NULL, tag DESC;`;
    }
    var value = [phone.replace(/\s+/g, ''), call_type];
    db.query(checkPhoneSql, value, (checkPhoneErr, checkPhoneResult) => {
        if (checkPhoneErr) {
            console.error('Error checking phone number:', checkPhoneErr);
            res.status(200).send('Error checking phone number');
            return;
        }
        if (checkPhoneResult.length > 0) {
            res.status(200).json(checkPhoneResult);
        } else {
            res.status(200).json([{ error: 'No data' }]);
        }
    });
});
app.get('/check-premium', (req, res) => {
    var id = req.query.id;
    var phone = req.query.phone;
    var checkPhoneSql = id
        ? `select premium,premium_start, premium_end, verification, verification_email from contacts where id =?;`
        : `select premium,premium_start, premium_end, verification, verification_email from contacts where phone_no =?;`;
    var value = [id || (phone ? phone.replace(/\s+/g, '') : '')];
    db.query(checkPhoneSql, value, (checkPhoneErr, checkPhoneResult) => {
        if (checkPhoneErr) {
            console.error('Error checking phone number:', checkPhoneErr);
            res.status(200).send('Error checking phone number');
            return;
        }
        if (checkPhoneResult.length > 0) {
            res.status(200).json(checkPhoneResult);
        } else {
            res.status(200).json([{ error: 'No data' }]);
        }
    });
});
app.post('/savepremium', (req, res) => {
    const { id, phone_no, premium, premium_start, premium_end } = req.body;
    var updateQuery = id
        ? "update `contacts` set premium=?, premium_start=FROM_UNIXTIME(?), premium_end=FROM_UNIXTIME(?) where id=?;"
        : "update `contacts` set premium=?, premium_start=FROM_UNIXTIME(?), premium_end=FROM_UNIXTIME(?) where phone_no=?;";
    var updateValues = [premium, Math.floor(parseInt(premium_start) / 1000), Math.floor(parseInt(premium_end) / 1000), id || phone_no];

    db.query(updateQuery, updateValues, (updateErr, updateResult) => {
        if (updateErr) {
            console.error(updateErr);
            res.status(500).send('Error updating call count');
        } else {
            console.log('Premium Upgrade');
            res.status(200).send('Premium Upgrade');
        }
    });
});
app.post('/updateverify', (req, res) => {
    const { id, phone, email } = req.body;
    var checkQuery = id ? "SELECT * FROM `contacts` WHERE id = ?;" : "SELECT * FROM `contacts` WHERE phone_no = ?;";
    var checkValues = [id || phone];

    db.query(checkQuery, checkValues, (checkErr, checkResult) => {
        if (checkErr) {
            console.error(checkErr);
            res.status(500).send('Error checking phone number');
        } else {
            if (checkResult.length === 0) {
                res.status(200).send('Phone number not found');
            } else {
                var updateQuery;
                if (email == null) {
                    updateQuery = id ? "UPDATE `contacts` SET verification = 1, publish='yes' WHERE id = ?;" : "UPDATE `contacts` SET verification = 1, publish='yes' WHERE phone_no = ?;";
                } else {
                    updateQuery = id ? "UPDATE `contacts` SET verification_email = 1 WHERE id = ?;" : "UPDATE `contacts` SET verification_email = 1 WHERE phone_no = ?;";
                }
                var updateValues = [id || phone];

                db.query(updateQuery, updateValues, (updateErr, updateResult) => {
                    if (updateErr) {
                        console.error(updateErr);
                        res.status(500).send('Error updating phone number');
                    } else {
                        console.log('Phone number verified');
                        res.status(200).send('Phone number verified');
                    }
                });
            }
        }
    });
});

app.get('/check-priority', (req, res) => {
    var id = req.query.id;
    var phone = req.query.phone;
    var checkPhoneSql = id ? `select * from contacts where id =?;` : `select * from contacts where phone_no =?;`;
    var value = [id || phone];
    db.query(checkPhoneSql, value, (checkPhoneErr, checkPhoneResult) => {
        if (checkPhoneErr) {
            console.error('Error checking phone number:', checkPhoneErr);
            res.status(200).send('Error checking phone number');
            return;
        }
        if (checkPhoneResult.length > 0) {
            res.status(200).json(checkPhoneResult);
        } else {
            res.status(200).json([{ error: 'No data' }]);
        }
    });
});
app.post('/savepriority', (req, res) => {
    const { id, phone, priority_amount, priority, owner } = req.body;
    var updateQuery = id ? "update `contacts` set priority=?, priority_balance=?, owner=? where id=?;" : "update `contacts` set priority=?, priority_balance=?, owner=? where phone_no=?;";
    var updateValues = [priority, priority_amount, owner, id || phone];

    db.query(updateQuery, updateValues, (updateErr, updateResult) => {
        if (updateErr) {
            console.error(updateErr);
            res.status(500).send('Error updating Priority');
        } else {
            //console.log('Priority updated');
            res.status(200).send('Priority updated');
        }
    });
});
app.post('/savepromote', (req, res) => {
    const { id, phone, international, country, state, city } = req.body;
    var updateQuery = id ? "update `contacts` set promote_international=?, promote_country=?, promote_state=?, promote_city=? where id=?;" : "update `contacts` set promote_international=?, promote_country=?, promote_state=?, promote_city=? where phone_no=?;";
    var updateValues = [international, country, state, city, id || phone];

    db.query(updateQuery, updateValues, (updateErr, updateResult) => {
        if (updateErr) {
            console.error(updateErr);
            res.status(500).send('Error updating Priority');
        } else {
            //console.log('Priority updated');
            res.status(200).send('Priority updated');
        }
    });
});
app.post('/savepriorityamount', (req, res) => {
    const { id, phone, phone1, priority_amount } = req.body;
    var updateQuery = id ? "update `contacts` set priority_balance = priority_balance + ? where id=?;" : "update `contacts` set priority_balance = priority_balance + ? where phone_no=? and phone_no=?;";
    var updateValues = id ? [priority_amount, id] : [priority_amount, phone, phone1 || phone];

    db.query(updateQuery, updateValues, (updateErr, updateResult) => {
        if (updateErr) {
            console.error(updateErr);
            res.status(500).send('Error updating Priority');
        } else {
            //console.log('Priority updated');
            res.status(200).send('Priority amount saved');
        }
    });
});
app.get('/check_search_type', (req, res) => {
    var id = req.query.id;
    var phone = req.query.phone ? req.query.phone.replace(/\s+/g, '') : '';

    // Query 1: Get Contact Details (prioritize ID)
    var contactSql = id ? `SELECT * FROM contacts WHERE id = ?;` : `SELECT * FROM contacts WHERE phone_no = ?;`;
    var contactParam = id || phone;

    db.query(contactSql, [contactParam], (err, contactResult) => {
        if (err) return res.status(200).json([{ error: 'Error' }]);
        if (contactResult.length === 0) return res.status(200).json([{ error: 'No data' }]);

        let contactData = contactResult[0];
        const contactPhone = (contactData.phone_no || phone).replace(/\s+/g, '');
        // Query 2: Get Reviews for this contact
        var reviewsSql = `SELECT * FROM reviews WHERE contact_phone = ? ORDER BY created DESC;`;

        db.query(reviewsSql, [contactPhone], (revErr, reviewsResult) => {
            if (revErr) return res.status(200).json([{ error: 'Error reviews' }]);

            // MERGE: Add the reviews list into the contact object
            contactData.reviews = reviewsResult || [];

            // Return as array to keep Flutter compatibility
            res.status(200).json([contactData]);
        });
    });
});
app.get('/check_search_type1', (req, res) => {
    var email = req.query.email
    var checkPhoneSql = `select * from contacts where owner_email =? and deleted_contact=0;`;
    var value = [email];
    db.query(checkPhoneSql, value, (checkPhoneErr, checkPhoneResult) => {
        if (checkPhoneErr) {
            console.error('Error checking phone number:', checkPhoneErr);
            res.status(200).send('Error checking phone number');
            return;
        }
        if (checkPhoneResult.length > 0) {
            var updateQuery = "UPDATE contacts SET deleted_contact=0 WHERE owner_email = ?";//delete from contacts where phone_no=?";
            var updateValues = [email];

            db.query(updateQuery, updateValues, (updateErr, updateResult) => {
                if (updateErr) {
                    console.error(updateErr);
                    res.status(500).send('Error updating call count');
                } else {
                    //console.log('Phone no deleted');
                    res.status(200).json(checkPhoneResult);
                }
            });
        } else {
            res.status(200).json([{ error: 'No data' }]);
        }
    });
});
app.post('/save_review', (req, res) => {
    // Extract data from the Flutter app's POST request
    const contact_phone = req.body.contact_phone;
    const reviewer_name = req.body.reviewer_name;
    const reviewer_phone = req.body.reviewer_phone;
    const rating = req.body.rating;
    const comment = req.body.comment;

    // Simple validation
    if (!contact_phone || !reviewer_name || !rating) {
        return res.status(200).json({ error: 'Missing required fields' });
    }

    const saveReviewSql = `
        INSERT INTO reviews (contact_phone, reviewer_name, reviewer_phone, rating, comment) 
        VALUES (?, ?, ?, ?, ?);
    `;

    const values = [
        contact_phone.replace(/\s+/g, ''),
        reviewer_name,
        reviewer_phone.replace(/\s+/g, ''),
        rating,
        comment
    ];

    db.query(saveReviewSql, values, (err, result) => {
        if (err) {
            console.error('Error saving review:', err);
            res.status(200).json({ error: 'Database error while saving review' });
            return;
        }

        // Return "success" so the Flutter app knows to refresh the screen
        res.status(200).json({ status: 'success', message: 'Review saved successfully' });
    });
});
app.post('/save_search_type', (req, res) => {
    const { id, phone, type, publish, who_contact } = req.body;
    var updateQuery = id ? "update `contacts` set search_type=?, publish=?, who_contact=? where id=?;" : "update `contacts` set search_type=?, publish=?, who_contact=? where phone_no=?;";
    var updateValues = [type, publish, who_contact, id || phone];

    db.query(updateQuery, updateValues, (updateErr, updateResult) => {
        if (updateErr) {
            console.error(updateErr);
            res.status(500).send('Error updating search type');
        } else {
            //console.log('Priority updated');
            res.status(200).send('Search type updated');
        }
    });
});
app.post('/save_search_type1', (req, res) => {
    const { id, phone, type } = req.body;
    var updateQuery = id ? "update `contacts` set search_type=? where id=?;" : "update `contacts` set search_type=? where phone_no=?;";
    var updateValues = [type, id || phone];

    db.query(updateQuery, updateValues, (updateErr, updateResult) => {
        if (updateErr) {
            console.error(updateErr);
            res.status(500).send('Error updating search type');
        } else {
            //console.log('Priority updated');
            res.status(200).send('Search type updated');
        }
    });
});
app.post('/save_publish', (req, res) => {
    const { id, phone, publish } = req.body;
    var updateQuery = id ? "update `contacts` set publish=? where id=?;" : "update `contacts` set publish=? where phone_no=?;";
    var updateValues = [publish, id || phone];

    db.query(updateQuery, updateValues, (updateErr, updateResult) => {
        if (updateErr) {
            console.error(updateErr);
            res.status(500).send('Error updating search type');
        } else {
            //console.log('Priority updated');
            res.status(200).send('Search type updated');
        }
    });
});
app.post('/save_access', (req, res) => {
    const { id, phone, who_contact } = req.body;
    var updateQuery = id ? "update `contacts` set who_contact=? where id=?;" : "update `contacts` set who_contact=? where phone_no=?;";
    var updateValues = [who_contact, id || phone];

    db.query(updateQuery, updateValues, (updateErr, updateResult) => {
        if (updateErr) {
            console.error(updateErr);
            res.status(500).send('Error updating search type');
        } else {
            //console.log('Priority updated');
            res.status(200).send('Search type updated');
        }
    });
});
app.post('/save_show', (req, res) => {
    const { id, phone, show } = req.body;
    var updateQuery = id ? "update `contacts` set show_contact=? where id=?;" : "update `contacts` set show_contact=? where phone_no=?;";
    var updateValues = [show, id || phone];

    db.query(updateQuery, updateValues, (updateErr, updateResult) => {
        if (updateErr) {
            console.error(updateErr);
            res.status(500).send('Error updating search type');
        } else {
            //console.log('Priority updated');
            res.status(200).send('Search type updated');
        }
    });
});
app.post('/savephonenos', (req, res) => {
    const { id, phone, output } = req.body;
    var updateQuery = id ? "update `contacts` set phonenos=? where id=?;" : "update `contacts` set phonenos=? where phone_no=?;";
    var updateValues = [output, id || phone];

    db.query(updateQuery, updateValues, (updateErr, updateResult) => {
        if (updateErr) {
            console.error(updateErr);
            res.status(500).send('Error updating phone nos');
        } else {
            //console.log('Priority updated');
            res.status(200).send('Phone nos updated');
        }
    });
});
const db1 = mysql.createConnection({
    host: 'localhost',
    user: 'root',
    password: 'Plestar@7542',
    database: 'printer_app'
});

db1.connect((err) => {
    if (err) {
        console.error('Error connecting to MySQL:', err.message);
        return;
    }
    console.log('Connected to MySQL');
});
app.post('/saveprinter', (req, res) => {
    const { phone, email, name, address, country } = req.body;
    const checkQuery = "SELECT * FROM `printer_details` WHERE `email` = ?";
    db1.query(checkQuery, [email], (checkErr, checkResult) => {
        if (checkErr) {
            console.error(checkErr);
            res.status(500).send('Error checking printer details');
        } else {
            if (checkResult.length > 0) {
                const updateQuery = "UPDATE `printer_details` SET `phone` = ?, name=?, address=?, country=? WHERE `email` = ?";
                const updateValues = [phone, name, address, country, email];

                db1.query(updateQuery, updateValues, (updateErr, updateResult) => {
                    if (updateErr) {
                        console.error(updateErr);
                        res.status(500).send('Error updating phone number');
                    } else {
                        res.status(200).send("Printer details saved");
                    }
                });
            } else {
                const insertQuery = "INSERT INTO `printer_details` (`phone`, `email`, name, address, country) VALUES (?, ?, ?, ?, ?);";
                const insertValues = [phone, email, name, address, country];

                db1.query(insertQuery, insertValues, (insertErr, insertResult) => {
                    if (insertErr) {
                        console.error(insertErr);
                        res.status(500).send('Error inserting printer details');
                    } else {
                        res.status(200).send('Printer details saved');
                    }
                });
            }
        }
    });
});

app.get('/getemail', (req, res) => {
    var phone = req.query.phone;
    var checkPhoneSql = `select * from printer_details where phone like concat("%",?,"%");`;
    var value = [phone.replace(/\s+/g, '')];
    db1.query(checkPhoneSql, value, (checkPhoneErr, checkPhoneResult) => {
        if (checkPhoneErr) {
            console.error('Error checking phone number:', checkPhoneErr);
            res.status(200).send('Error checking phone number');
            return;
        }
        if (checkPhoneResult.length > 0) {
            res.status(200).json(checkPhoneResult);
        } else {
            res.status(200).json([{ error: 'No data' }]);
        }
    });
});
app.post('/delete_printer', (req, res) => {
    const { email } = req.body;
    var updateQuery = "delete from printer_details where email=?";
    var updateValues = [email];

    db1.query(updateQuery, updateValues, (updateErr, updateResult) => {
        if (updateErr) {
            console.error(updateErr);
            res.status(500).send('Error deleting printer');
        } else {
            console.log('Phone no deleted');
            res.status(200).send('printer deleted');
        }
    });
});
const gmailEmail = 'otp@tpdirectory.com';
const gmailPassword = 'bueh rpwu zvxd goky';

const transporter = nodemailer.createTransport({
    service: 'gmail',
    auth: {
        user: gmailEmail,
        pass: gmailPassword
    }
});

app.post('/send-verification-code', (req, res) => {
    const { email, otp } = req.body;

    // Safely get identification, default to empty string if missing
    const fone_id = (req.body.fone_identification || '').toString().toLowerCase();

    // Default Branding (TP Directory)
    let appName = "Telephone Directory App";
    let bannerUrl = "https://apps.plestarinc.com/uploads/tpdirectory.webp";

    // Switch to FoneBook Branding if identified
    if (fone_id === 'fonebook') {
        appName = "Fone book";
        bannerUrl = "https://apps.plestarinc.com/uploads/fonebook_banner.jpg";
    }

    const mailOptions = {
        from: `"${appName}" <${gmailEmail}>`,
        to: email,
        subject: `Verification Code - ${appName}`,
        html: `<div>
                <p>Your Verification Code is <b>${otp}</b>. ${appName}.</p>
                <br>
                <img src="${bannerUrl}" alt="Banner" style="width:400px;height:auto;"/>
            </div>`
    };

    transporter.sendMail(mailOptions, (error, info) => {
        if (error) {
            console.error('Error sending email:', error);
            res.status(200).json({ status: 'error', message: 'Error sending verification code' });
        } else {
            res.status(200).json({ status: 'success', message: 'Verification email sent' });
        }
    });
});


const parsePhoneNumber = (phoneStr) => {
    if (!phoneStr) return { dialCode: '+91', national: '', key: '+91-' };

    let clean = phoneStr.replace(/[\(\)\-\s\.]/g, '').trim();

    const dialCodes = [
        '+880', '+971', '+966', '+355', '+213', '+376', '+244', '+374', '+994', '+375',
        '+501', '+229', '+975', '+591', '+387', '+267', '+673', '+359', '+226', '+257',
        '+855', '+237', '+238', '+236', '+235', '+56', '+86', '+57', '+269', '+242',
        '+506', '+385', '+53', '+357', '+420', '+45', '+253', '+593', '+20', '+503',
        '+240', '+291', '+372', '+251', '+500', '+298', '+679', '+358', '+33', '+594',
        '+689', '+241', '+220', '+995', '+49', '+233', '+350', '+30', '+299', '+502',
        '+224', '+245', '+592', '+509', '+504', '+852', '+36', '+354', '+91', '+62',
        '+98', '+964', '+353', '+972', '+39', '+225', '+870', '+962', '+7', '+254',
        '+686', '+850', '+82', '+965', '+996', '+856', '+371', '+961', '+266', '+231',
        '+218', '+423', '+370', '+352', '+853', '+389', '+261', '+265', '+60', '+960',
        '+223', '+356', '+692', '+596', '+222', '+230', '+262', '+52', '+691', '+373',
        '+377', '+976', '+382', '+212', '+258', '+95', '+264', '+674', '+977', '+31',
        '+599', '+687', '+64', '+505', '+227', '+234', '+683', '+47', '+968', '+92',
        '+680', '+507', '+675', '+595', '+51', '+63', '+48', '+351', '+974', '+40',
        '+250', '+290', '+508', '+685', '+378', '+239', '+966', '+221', '+381', '+248',
        '+232', '+65', '+421', '+386', '+677', '+252', '+27', '+34', '+94', '+249',
        '+597', '+268', '+46', '+41', '+963', '+886', '+992', '+255', '+66', '+670',
        '+228', '+676', '+216', '+90', '+993', '+688', '+256', '+380', '+971', '+44',
        '+1', '+598', '+998', '+678', '+58', '+84', '+681', '+967', '+260', '+263'
    ];

    let matchedCode = '';
    if (clean.startsWith('+')) {
        for (const dc of dialCodes) {
            if (clean.startsWith(dc)) {
                matchedCode = dc;
                clean = clean.substring(dc.length);
                break;
            }
        }
    }

    let digits = clean.replace(/[^\d]/g, '');
    if (digits.length > 10 && digits.startsWith('0')) {
        digits = digits.substring(1);
    }

    if (!matchedCode) {
        matchedCode = '+91';
    }

    const national = digits.length >= 10 ? digits.slice(-10) : digits;
    return {
        dialCode: matchedCode,
        national: national,
        key: `${matchedCode}-${national}`,
        formatted: `${matchedCode} ${national}`
    };
};

const getCleanPhone = (phone) => {
    return parsePhoneNumber(phone).key;
};


const getOwnerContactsArray = (ownerEmail, callback) => {
    db.query("SELECT contacts FROM my_contacts WHERE owner_email = ?", [ownerEmail], (err, results) => {
        if (err) {
            console.error("Error querying my_contacts:", err);
            return callback(err, []);
        }
        if (results && results.length > 0 && results[0].contacts) {
            try {
                const list = JSON.parse(results[0].contacts);
                return callback(null, list);
            } catch (e) {
                console.error("JSON parse error in my_contacts:", e);
            }
        }
        callback(null, []);
    });
};


const saveOwnerContactsArray = (ownerEmail, list, callback) => {
    const jsonStr = JSON.stringify(list);
    const query = "INSERT INTO my_contacts (owner_email, contacts) VALUES (?, ?) ON DUPLICATE KEY UPDATE contacts = VALUES(contacts)";
    db.query(query, [ownerEmail, jsonStr], (err) => {
        if (err) console.error("Error saving my_contacts array:", err);
        callback(err);
    });
};

const isProfileItem = (item, reqBody = {}) => {
    if (!item && !reqBody) return false;
    const cat = (item?.category || reqBody?.category || '').toLowerCase();
    const action = (reqBody?.action || '').toLowerCase();
    const appProf = item?.app_profile || reqBody?.app_profile || reqBody?.profile;
    const titleStr = item?.title || reqBody?.title || '';

    if (cat === 'app_profile' || action === 'save_my_profile') return true;
    if (appProf && typeof appProf === 'string' && appProf.trim().length > 0 && appProf !== 'null' && appProf.startsWith('{')) return true;
    if (typeof titleStr === 'string' && titleStr.startsWith('{') && (titleStr.includes('"owner_email"') || titleStr.includes('"full_name"') || titleStr.includes('"address"') || titleStr.includes('"pincode"'))) return true;
    return false;
};

app.post('/save_my_contact', (req, res) => {
    const { owner_email, name, title, phone, email, category, app_profile, profile, type } = req.body;
    const userEmail = owner_email || email || req.body.phone || 'guest@fonebook.com';
    if (!phone) {
        return res.status(400).json({ error: 'Phone is required' });
    }
    const parsed = parsePhoneNumber(phone);
    if (!parsed.national) {
        return res.status(400).json({ error: 'Invalid phone number' });
    }

    const isProfile = isProfileItem({ category, title, app_profile: app_profile || profile, type }, req.body);

    getOwnerContactsArray(userEmail, (err, list) => {
        if (err) return res.status(500).json({ error: 'Database error' });

        let currentList = Array.isArray(list) ? list : [];

        if (isProfile) {
            // Updating / Saving User Profile: Keep only one profile entry per account
            const profilePayloadStr = app_profile || profile || title || '';
            const existingProfIdx = currentList.findIndex(c => isProfileItem(c));

            if (existingProfIdx !== -1) {
                // Update existing profile in place
                const existingProf = currentList[existingProfIdx];
                currentList[existingProfIdx] = {
                    ...existingProf,
                    name: name || existingProf.name || '',
                    title: profilePayloadStr || existingProf.title || '',
                    phone: parsed.formatted,
                    category: 'app_profile',
                    app_profile: profilePayloadStr,
                    updated_at: new Date().toISOString()
                };
                // Remove any duplicate profile rows if they exist
                currentList = currentList.filter((c, idx) => idx === existingProfIdx || !isProfileItem(c));
            } else {
                // Insert new profile row
                const newProfile = {
                    id: Date.now(),
                    owner_email: userEmail,
                    name: name || '',
                    title: profilePayloadStr,
                    phone: parsed.formatted,
                    category: 'app_profile',
                    app_profile: profilePayloadStr,
                    created_at: new Date().toISOString()
                };
                currentList.unshift(newProfile);
            }

            saveOwnerContactsArray(userEmail, currentList, (saveErr) => {
                if (saveErr) return res.status(500).json({ error: 'Error saving profile' });
                res.status(200).json({ message: 'Profile saved successfully' });
            });
        } else {
            // Saving normal contact: check duplicate against non-profile contacts
            const existing = currentList.find(c => !isProfileItem(c) && parsePhoneNumber(c.phone).key === parsed.key);
            if (existing) {
                return res.status(400).json({ error: 'Number is already in contacts' });
            }

            const newId = Date.now();
            const newContact = {
                id: newId,
                owner_email: userEmail,
                name: name || '',
                title: title || '',
                phone: parsed.formatted,
                category: category || 'my_contact',
                created_at: new Date().toISOString()
            };

            currentList.unshift(newContact);

            saveOwnerContactsArray(userEmail, currentList, (saveErr) => {
                if (saveErr) return res.status(500).json({ error: 'Error saving contact' });
                res.status(200).json({ message: 'Contact saved successfully' });
            });
        }
    });
});

app.post('/update_my_contact', (req, res) => {
    const { id, owner_email, name, title, phone, category, app_profile, profile, type } = req.body;
    if (!id && !category && !title) {
        return res.status(400).json({ error: 'ID or profile data is required' });
    }
    const parsed = parsePhoneNumber(phone);
    const userEmail = owner_email || req.body.email || 'guest@fonebook.com';
    const isProfile = isProfileItem({ category, title, app_profile: app_profile || profile, type }, req.body);

    getOwnerContactsArray(userEmail, (err, list) => {
        if (err) return res.status(500).json({ error: 'Database error' });

        let currentList = Array.isArray(list) ? list : [];

        if (isProfile) {
            const profilePayloadStr = app_profile || profile || title || '';
            let profIdx = currentList.findIndex(c => (id && String(c.id) === String(id)) || isProfileItem(c));

            if (profIdx !== -1) {
                const existingProf = currentList[profIdx];
                currentList[profIdx] = {
                    ...existingProf,
                    name: name !== undefined ? name : existingProf.name,
                    title: profilePayloadStr || existingProf.title || '',
                    phone: parsed.national ? parsed.formatted : existingProf.phone,
                    category: 'app_profile',
                    app_profile: profilePayloadStr,
                    updated_at: new Date().toISOString()
                };
                // Deduplicate any other profile entries
                currentList = currentList.filter((c, idx) => idx === profIdx || !isProfileItem(c));
            } else {
                currentList.unshift({
                    id: id ? (parseInt(id) || Date.now()) : Date.now(),
                    owner_email: userEmail,
                    name: name || '',
                    title: profilePayloadStr,
                    phone: parsed.national ? parsed.formatted : (phone || ''),
                    category: 'app_profile',
                    app_profile: profilePayloadStr,
                    created_at: new Date().toISOString()
                });
            }

            saveOwnerContactsArray(userEmail, currentList, (saveErr) => {
                if (saveErr) return res.status(500).json({ error: 'Error updating profile' });
                res.status(200).json({ message: 'Profile updated successfully' });
            });
        } else {
            // Normal contact update
            const existing = currentList.find(c => !isProfileItem(c) && parsePhoneNumber(c.phone).key === parsed.key && String(c.id) !== String(id));
            if (existing) {
                return res.status(400).json({ error: 'Number is already in contacts' });
            }

            const idx = currentList.findIndex(c => String(c.id) === String(id));
            if (idx !== -1) {
                currentList[idx].name = name !== undefined ? name : currentList[idx].name;
                currentList[idx].title = title !== undefined ? title : currentList[idx].title;
                if (parsed.national) currentList[idx].phone = parsed.formatted;
                if (category) currentList[idx].category = category;
            }

            saveOwnerContactsArray(userEmail, currentList, (saveErr) => {
                if (saveErr) return res.status(500).json({ error: 'Error updating contact' });
                res.status(200).json({ message: 'Contact updated successfully' });
            });
        }
    });
});

app.post(['/bulk_assign_category', '/update_contact_category', '/assign_contact_category'], (req, res) => {
    let { owner_email, email, phone, phones, ids, category } = req.body;
    const userEmail = owner_email || email || 'guest@fonebook.com';
    const targetCategory = (category || '').trim();

    if (typeof phones === 'string') {
        try { phones = JSON.parse(phones); } catch (_) { phones = phones.split(',').map(s => s.trim()).filter(Boolean); }
    }
    if (typeof ids === 'string') {
        try { ids = JSON.parse(ids); } catch (_) { ids = ids.split(',').map(s => s.trim()).filter(Boolean); }
    }

    const phoneSet = new Set();
    if (phone) phoneSet.add(getCleanPhone(phone));
    if (Array.isArray(phones)) phones.forEach(p => phoneSet.add(getCleanPhone(p)));

    const idSet = new Set();
    if (Array.isArray(ids)) ids.forEach(i => idSet.add(String(i)));

    getOwnerContactsArray(userEmail, (err, list) => {
        if (err) return res.status(500).json({ error: 'Database error' });

        const rawList = Array.isArray(list) ? list : [];
        let updatedCount = 0;

        for (let i = 0; i < rawList.length; i++) {
            if (isProfileItem(rawList[i])) continue;

            const c = rawList[i];
            const cleanP = getCleanPhone(c.phone);
            const matchesPhone = phoneSet.size > 0 && phoneSet.has(cleanP);
            const matchesId = idSet.size > 0 && idSet.has(String(c.id));

            if (matchesPhone || matchesId) {
                rawList[i].category = targetCategory;
                updatedCount++;
            }
        }

        saveOwnerContactsArray(userEmail, rawList, (saveErr) => {
            if (saveErr) return res.status(500).json({ error: 'Error updating categories' });
            res.status(200).json({
                status: 'success',
                message: `Updated category for ${updatedCount} contact(s)`,
                updated_count: updatedCount
            });
        });
    });
});

app.post(['/delete_my_contact', '/bulk_delete_my_contacts'], (req, res) => {
    let { id, ids, phone, phones, owner_email, email, select_all, all } = req.body;
    const userEmail = owner_email || email || 'guest@fonebook.com';
    const isSelectAll = select_all === true || select_all === 'true' || all === true || all === 'true';

    if (typeof ids === 'string') {
        try { ids = JSON.parse(ids); } catch (_) { ids = ids.split(',').map(s => s.trim()).filter(Boolean); }
    }
    if (typeof phones === 'string') {
        try { phones = JSON.parse(phones); } catch (_) { phones = phones.split(',').map(s => s.trim()).filter(Boolean); }
    }

    const idSet = new Set();
    if (id) idSet.add(String(id));
    if (Array.isArray(ids)) ids.forEach(i => idSet.add(String(i)));

    const phoneSet = new Set();
    if (phone) phoneSet.add(getCleanPhone(phone));
    if (Array.isArray(phones)) phones.forEach(p => phoneSet.add(getCleanPhone(p)));

    getOwnerContactsArray(userEmail, (err, list) => {
        if (err) return res.status(500).json({ error: 'Database error' });

        const rawList = Array.isArray(list) ? list : [];
        const initialCount = rawList.length;
        let updatedList = [];

        if (isSelectAll) {
            // Delete all non-profile contacts, preserve the user profile
            updatedList = rawList.filter(c => isProfileItem(c));
        } else {
            // Delete matching contacts by id or phone, preserving user profile
            updatedList = rawList.filter(c => {
                if (isProfileItem(c)) return true;
                if (idSet.size > 0 && idSet.has(String(c.id))) return false;
                if (phoneSet.size > 0 && phoneSet.has(getCleanPhone(c.phone))) return false;
                return true;
            });
        }

        const deletedCount = initialCount - updatedList.length;

        saveOwnerContactsArray(userEmail, updatedList, (saveErr) => {
            if (saveErr) return res.status(500).json({ error: 'Error deleting contacts' });
            res.status(200).json({
                status: 'success',
                message: `Successfully deleted ${deletedCount} contact(s)`,
                deleted_count: deletedCount
            });
        });
    });
});

app.post('/delete_account', (req, res) => {
    const { owner_email, email, phone } = req.body;
    const userEmail = (owner_email || email || '').trim();
    const cleanPhone = phone ? getCleanPhone(phone) : '';

    if (!userEmail && !cleanPhone) {
        return res.status(400).json({ error: 'Email or phone required to delete account' });
    }

    console.log(`[DELETE_ACCOUNT] Request to permanently delete account: email=${userEmail}, phone=${cleanPhone}`);

    // 1. Delete from my_contacts table (removes app_profile and all saved contacts)
    const deleteMyContactsQuery = "DELETE FROM my_contacts WHERE owner_email = ?";
    db.query(deleteMyContactsQuery, [userEmail], (err1) => {
        if (err1) console.error("Error deleting from my_contacts:", err1);

        // 2. Delete business profiles and contacts from contacts table
        const deleteContactsQuery = "DELETE FROM contacts WHERE owner_email = ? OR email = ?" + (cleanPhone ? " OR phone_no LIKE ?" : "");
        const params = [userEmail, userEmail];
        if (cleanPhone) params.push(`%${cleanPhone}%`);

        db.query(deleteContactsQuery, params, (err2) => {
            if (err2) console.error("Error deleting from contacts table:", err2);

            // 3. Clear reviews if any
            if (cleanPhone) {
                db.query("DELETE FROM reviews WHERE contact_phone LIKE ? OR reviewer_phone LIKE ?", [`%${cleanPhone}%`, `%${cleanPhone}%`], (err3) => {
                    if (err3) console.error("Error deleting from reviews:", err3);
                });
            }

            console.log(`[DELETE_ACCOUNT] Successfully deleted all data for user ${userEmail}`);
            res.status(200).json({
                status: 'success',
                message: 'Account and all associated data permanently deleted.'
            });
        });
    });
});

app.post('/import_my_contacts', (req, res) => {
    let { owner_email, contacts, email, phone } = req.body;
    const userEmail = owner_email || email || phone || 'guest@fonebook.com';
    if (typeof contacts === 'string') {
        try { contacts = JSON.parse(contacts); } catch (_) { }
    }
    if (!Array.isArray(contacts) || contacts.length === 0) {
        return res.status(400).json({ error: 'Invalid request body: contacts array required' });
    }

    getOwnerContactsArray(userEmail, (err, list) => {
        if (err) return res.status(500).json({ error: 'Database error' });

        const currentList = Array.isArray(list) ? list : [];
        const existingKeys = new Set(currentList.filter(c => !isProfileItem(c)).map(c => parsePhoneNumber(c.phone).key));
        let insertedCount = 0;
        let skippedCount = 0;

        for (const c of contacts) {
            const p = parsePhoneNumber(c.phone);
            if (!p.national) continue;
            if (existingKeys.has(p.key)) {
                skippedCount++;
            } else {
                existingKeys.add(p.key);
                insertedCount++;
                currentList.unshift({
                    id: Date.now() + Math.floor(Math.random() * 10000),
                    owner_email: userEmail,
                    name: c.name || '',
                    title: c.title || '',
                    phone: p.formatted,
                    category: c.category || 'my_contact',
                    created_at: new Date().toISOString()
                });
            }
        }

        saveOwnerContactsArray(userEmail, currentList, (saveErr) => {
            if (saveErr) return res.status(500).json({ error: 'Database error' });
            res.status(200).json({
                message: 'Import completed',
                inserted: insertedCount,
                skipped: skippedCount
            });
        });
    });
});

app.all('/get_my_contacts', (req, res) => {
    const email = req.body.email || req.body.owner_email || req.query.email || req.query.owner_email || 'guest@fonebook.com';
    getOwnerContactsArray(email, (err, list) => {
        if (err) return res.status(500).json({ error: 'Database error' });

        const rawList = Array.isArray(list) ? list : [];
        const seenContacts = new Set();
        const results = [];
        let profileAdded = false;

        for (const item of rawList) {
            if (isProfileItem(item)) {
                if (!profileAdded) {
                    profileAdded = true;
                    results.push({
                        ...item,
                        category: 'app_profile',
                        app_profile: item.app_profile || item.title || null
                    });
                }
            } else {
                const cleanP = getCleanPhone(item.phone);
                if (cleanP && !seenContacts.has(cleanP)) {
                    seenContacts.add(cleanP);
                    results.push(item);
                } else if (!cleanP) {
                    results.push(item);
                }
            }
        }
        res.status(200).json(results);
    });
});