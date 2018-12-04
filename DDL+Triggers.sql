CREATE SCHEMA PHARMA_MANUFACTURING;

SET SEARCH_PATH TO PHARMA_MANUFACTURING;

CREATE TABLE Material_Master(

	Material_ID VARCHAR(20) PRIMARY KEY,
	Material_Name VARCHAR(30) NOT NULL,
	Material_Type VARCHAR(20) NOT NULL,
	Storage_Condition VARCHAR(100) NOT NULL,
	Shelf_Life NUMERIC(3) NOT NULL CHECK(Shelf_Life > 0),
	Therapeutic_Category VARCHAR(30) NOT NULL,
	Material_State VARCHAR(10) NOT NULL,
	isHazardous BOOLEAN NOT NULL,
	isInflammable BOOLEAN NOT NULL,
	UOM varchar(3) NOT NULL

);

CREATE TABLE Account_Master(

	Account_No VARCHAR(11) PRIMARY KEY,
	Account_Name VARCHAR(50) NOT NULL,
	Phone_No VARCHAR(13) NOT NULL,
	Address VARCHAR(100) NOT NULL

);

CREATE TABLE Transactions(

	Invoice_No NUMERIC(10) PRIMARY KEY,
	Transaction_Date DATE NOT NULL,
	Currency VARCHAR(3) NOT NULL,
	Transaction_Type VARCHAR(4) NOT NULL CHECK (Transaction_Type IN ('buy', 'sell')),
	Paid_Received BOOLEAN NOT NULL,
	Account_No VARCHAR(11) REFERENCES Account_Master(Account_No) ON DELETE CASCADE ON UPDATE CASCADE,
	Total_Value NUMERIC(10,2) NOT NULL CHECK(Total_Value > 0)

);

CREATE TABLE Warehouse(

	Material_ID VARCHAR(20)REFERENCES Material_Master(Material_ID) ON DELETE CASCADE ON UPDATE CASCADE,
	Invoice_No NUMERIC(10) REFERENCES Transactions(Invoice_No) ON DELETE CASCADE ON UPDATE CASCADE,
	UT_Q_A VARCHAR(2) NOT NULL,
	Stock NUMERIC(10) NOT NULL CHECK(Stock > 0),
	Val NUMERIC(10,2) NOT NULL CHECK(Val > 0),
	Buy_Qty NUMERIC(10) NOT NULL CHECK(Buy_Qty > 0),
	PRIMARY KEY (Invoice_No , Material_ID)

);
												
CREATE TABLE Material_Quality_Check(

	Material_ID VARCHAR(20),
	Invoice_No NUMERIC(10),
	Report_ID VARCHAR(20) PRIMARY KEY,
	Analysis_Date DATE NOT NULL,
	Analyst_Name VARCHAR(20) NOT NULL,
	Sample_Size NUMERIC(10) NOT NULL CHECK(Sample_Size > 0),
	Test VARCHAR(20) NOT NULL,
	Limits VARCHAR(20) NOT NULL,
	Results VARCHAR(30) NOT NULL,
	FOREIGN KEY (Material_id, Invoice_No) REFERENCES Warehouse(Material_id, Invoice_No) ON DELETE CASCADE ON UPDATE CASCADE

);												

CREATE TABLE Product_Master(

	Product_ID VARCHAR(20) PRIMARY KEY,
	Product_Name VARCHAR(20) NOT NULL,
	Generic_Name VARCHAR(100) NOT NULL,
	Product_Type VARCHAR(20) NOT NULL,
	Packing_type VARCHAR(10) NOT NULL,
	Packing_Size VARCHAR(5) NOT NULL,
	SalableorSample VARCHAR(1) NOT NULL CHECK (SalableorSample IN ('M', 'S')),
	GenericorBranded VARCHAR(1) NOT NULL CHECK (GenericorBranded IN ('G', 'B'))

);

CREATE TABLE Formula_Master(

	Product_ID VARCHAR(20) REFERENCES Product_Master(Product_ID) ON DELETE CASCADE ON UPDATE CASCADE,
	Material_ID VARCHAR(20) REFERENCES Material_Master(Material_ID) ON DELETE CASCADE ON UPDATE CASCADE,
	Weight_per_tablet NUMERIC(10) NOT NULL CHECK(Weight_per_tablet > 0),
	PRIMARY KEY (Product_ID , Material_ID)

);

CREATE TABLE Batch(

	Batch_No NUMERIC(10) PRIMARY KEY,
	Batch_Size NUMERIC(10) NOT NULL CHECK(Batch_Size > 0),
	Mfg_Date DATE NOT NULL,
	Exp_Date DATE,
	Product_ID VARCHAR(20) REFERENCES Product_Master(Product_ID) ON DELETE CASCADE ON UPDATE CASCADE,
	Stock_Qty NUMERIC(10) NOT NULL CHECK(Stock_Qty >= 0),
	UT_Q_A VARCHAR(2) NOT NULL

);

CREATE TABLE Material_Dispensing(

	Batch_No NUMERIC(10) REFERENCES Batch(Batch_No) ON DELETE CASCADE ON UPDATE CASCADE,
	Material_ID VARCHAR(20),
	Invoice_No NUMERIC(10),
	Quantity_Issued NUMERIC(10) NOT NULL CHECK(Quantity_Issued > 0),
	FOREIGN KEY (Material_id, Invoice_No) REFERENCES Warehouse(Material_id, Invoice_No) ON DELETE CASCADE ON UPDATE CASCADE,
	PRIMARY KEY (Batch_No , Material_ID, Invoice_No)

);

CREATE TABLE Product_Quality_Check(

	Batch_No NUMERIC(10) REFERENCES Batch(Batch_No) ON DELETE CASCADE ON UPDATE CASCADE,
	Report_ID VARCHAR(20) PRIMARY KEY,
	Analysis_Date DATE NOT NULL,
	Analyst_Name VARCHAR(20) NOT NULL,
	Sample_Size NUMERIC(10) NOT NULL CHECK(Sample_Size > 0),
	Process_State VARCHAR(20) NOT NULL,
	Test VARCHAR(20) NOT NULL,
	Limits VARCHAR(20) NOT NULL,
	Results VARCHAR(30) NOT NULL

);

CREATE TABLE FG_Transaction(

	Invoice_No NUMERIC(10) REFERENCES Transactions(Invoice_No) ON DELETE CASCADE ON UPDATE CASCADE,
	Batch_No NUMERIC(10) REFERENCES Batch(Batch_No) ON DELETE CASCADE ON UPDATE CASCADE,
	Sale_Qty NUMERIC(10) NOT NULL CHECK(Sale_Qty > 0),
	Val NUMERIC(10,2) NOT NULL CHECK(Val > 0),
	PRIMARY KEY (Invoice_No , Batch_No)

);

CREATE FUNCTION bmat()
RETURNS TRIGGER AS $body$
DECLARE
	iterator1 RECORD;
	iterator2 RECORD;
	reqstk NUMERIC(10);
	dupstk NUMERIC(10);
BEGIN
	IF (TG_OP = 'INSERT') THEN
		FOR iterator1 IN (SELECT * FROM Batch NATURAL JOIN Product_Master NATURAL JOIN Formula_Master WHERE Batch_No = NEW.Batch_No) LOOP
			reqstk := iterator1.Weight_per_tablet*NEW.Batch_Size*(0.001);
			FOR iterator2 IN (SELECT * FROM Warehouse WHERE Material_ID = iterator1.Material_ID AND UT_Q_A = 'A') LOOP
				IF (iterator2.Stock > reqstk) THEN
					dupstk := iterator2.Stock - reqstk;
					UPDATE Warehouse SET Stock = dupstk WHERE Material_ID = iterator2.Material_ID AND Invoice_No = iterator2.Invoice_No;
					INSERT INTO Material_Dispensing VALUES(NEW.Batch_No, iterator2.Material_ID, iterator2.Invoice_No, reqstk);
					EXIT;
				END IF;
			END LOOP;
		END LOOP;
		RETURN NEW;	
	END IF;
	IF (TG_OP = 'DELETE') THEN
		FOR iterator1 IN (SELECT * FROM Material_Dispensing WHERE Batch_No = OLD.Batch_No) LOOP
			SELECT Stock INTO dupstk FROM Warehouse WHERE Material_ID = iterator1.Material_ID AND Invoice_No = iterator1.Invoice_No;
			dupstk = dupstk + reqstk;
			UPDATE Warehouse SET Stock = dupstk WHERE Material_ID = iterator1.Material_ID AND Invoice_No = iterator1.Invoice_No;
		END LOOP;
		RETURN OLD;
	END IF;
	RETURN NULL;
END;
$body$ LANGUAGE 'plpgsql';

CREATE TRIGGER batch_materials
AFTER INSERT OR DELETE ON Batch FOR EACH ROW execute procedure bmat();
												
CREATE FUNCTION fgtobatch()
RETURNS TRIGGER AS $body$
DECLARE
	Stock NUMERIC(10);
BEGIN
	IF (TG_OP = 'INSERT') THEN
		SELECT Stock_Qty INTO Stock FROM Batch WHERE Batch_No = NEW.Batch_No;  
		Stock := Stock - NEW.Sale_Qty;
		UPDATE Batch SET Stock_Qty = Stock WHERE Batch_No = NEW.Batch_No;	
		RETURN NEW;	
	END IF;
	IF (TG_OP = 'UPDATE') THEN
		IF (NEW.Batch_No = OLD.Batch_No) THEN
			SELECT Stock_Qty INTO Stock FROM Batch WHERE Batch_No = NEW.Batch_No;  
			Stock := Stock + OLD.Sale_Qty - NEW.Sale_Qty;
			UPDATE Batch SET Stock_Qty = Stock WHERE Batch_No = NEW.Batch_No;
		ELSE
			SELECT Stock_Qty INTO Stock FROM Batch WHERE Batch_No = NEW.Batch_No;
			Stock := Stock - NEW.Sale_Qty;
			UPDATE Batch SET Stock_Qty = Stock WHERE Batch_No = NEW.Batch_No;
			SELECT Stock_Qty INTO Stock FROM Batch WHERE Batch_No = OLD.Batch_No;
			Stock := Stock + OLD.Sale_Qty;
			UPDATE Batch SET Stock_Qty = Stock WHERE Batch_No = OLD.Batch_No;
		END IF;			
		RETURN NEW;	
	END IF;
	IF (TG_OP = 'DELETE') THEN
		SELECT Stock_Qty INTO Stock FROM Batch WHERE Batch_No = OLD.Batch_No;  
		Stock := Stock + OLD.Sale_Qty;
		UPDATE Batch SET Stock_Qty = Stock WHERE Batch_No = OLD.Batch_No;	
		RETURN OLD;	
	END IF;
	RETURN NULL;
END;
$body$ LANGUAGE 'plpgsql';

CREATE TRIGGER batch_stock_change
AFTER INSERT OR UPDATE OR DELETE ON FG_Transaction
	FOR EACH ROW EXECUTE PROCEDURE fgtobatch();
												
CREATE FUNCTION fgtransactions_tally()
RETURNS VOID AS $body$
DECLARE
	iterator1 RECORD;
	iterator2 RECORD;
	sum NUMERIC(10,2);
BEGIN
	FOR iterator1 IN (SELECT * FROM Transactions WHERE Transaction_Type = 'sell') LOOP
		sum := 0;
		FOR iterator2 IN (SELECT * FROM Transactions NATURAL JOIN FG_Transaction WHERE Invoice_No = iterator1.Invoice_No) LOOP
			sum := sum + iterator2.Val;
		END LOOP;
		IF (sum != iterator1.Total_Value) THEN
			RAISE NOTICE 'Issue with Invoice_No %',iterator1.Invoice_No;
		END IF;
	END LOOP;
END;
$body$ LANGUAGE 'plpgsql';
												
CREATE FUNCTION fgval()
RETURNS TRIGGER AS $body$
DECLARE
	Stock NUMERIC(10);
	flag VARCHAR(3);
BEGIN
	IF (TG_OP = 'INSERT') THEN
		SELECT Stock_Qty INTO Stock FROM Batch WHERE Batch_No = NEW.Batch_No;
		SELECT UT_Q_A INTO flag FROM Batch WHERE Batch_No = NEW.Batch_No;  
		IF( NEW.Sale_Qty > Stock OR flag = 'UT' OR flag = 'Q') THEN
			RAISE EXCEPTION 'Order should be smaller than % and the batch should be approved',Stock;
		END IF;			
		RETURN NEW;	
	END IF;
	IF (TG_OP = 'UPDATE') THEN
		IF (NEW.Batch_No = OLD.Batch_No) THEN
			SELECT Stock_Qty INTO Stock FROM Batch WHERE Batch_No = NEW.Batch_No;
			SELECT UT_Q_A INTO flag FROM Batch WHERE Batch_No = NEW.Batch_No;  
			IF( NEW.Sale_Qty > Stock + OLD.Sale_Qty OR flag = 'UT' OR flag = 'Q') THEN
				RAISE EXCEPTION 'Order should be smaller than % and the batch should be approved',Stock;
			END IF;
		ELSE
			SELECT Stock_Qty INTO Stock FROM Batch WHERE Batch_No = NEW.Batch_No;
			SELECT UT_Q_A INTO flag FROM Batch WHERE Batch_No = NEW.Batch_No;
			IF( NEW.Sale_Qty > Stock OR flag = 'UT' OR flag = 'Q') THEN
				RAISE EXCEPTION 'Order should be smaller than % and the batch should be approved',Stock;
			END IF;
		END IF;			
		RETURN NEW;	
	END IF;
	RETURN NULL;
END;
$body$ LANGUAGE 'plpgsql';

CREATE TRIGGER fgvalidation
BEFORE INSERT OR UPDATE ON FG_Transaction
	FOR EACH ROW EXECUTE PROCEDURE fgval();
												
CREATE FUNCTION rmqc_date()
RETURNS TRIGGER AS $body$
DECLARE
	buydate DATE;
BEGIN
	IF (TG_OP = 'INSERT' OR TG_OP = 'UPDATE') THEN
		SELECT Transaction_Date INTO buydate FROM Warehouse NATURAL JOIN Transactions WHERE Material_ID = NEW.Material_ID AND Invoice_No = NEW.Invoice_No;
		IF( NEW.Analysis_Date < buydate) THEN
			RAISE EXCEPTION 'Analysis Date should be same as % or after it',buydate;
		END IF;			
		RETURN NEW;	
	END IF;
	RETURN NULL;
END;
$body$ LANGUAGE 'plpgsql';

CREATE TRIGGER material_qc_date
BEFORE INSERT OR UPDATE ON Material_Quality_Check
	FOR EACH ROW EXECUTE PROCEDURE rmqc_date();
												
CREATE FUNCTION rmqc()
RETURNS TRIGGER AS $body$
BEGIN
	IF (TG_OP = 'INSERT') THEN
		IF (NEW.Results = 'PASSED') THEN
			UPDATE Warehouse SET UT_Q_A = 'A' WHERE Material_ID = NEW.Material_ID AND Invoice_No = NEW.Invoice_No;
		ELSE
			UPDATE Warehouse SET UT_Q_A = 'Q' WHERE Material_ID = NEW.Material_ID AND Invoice_No = NEW.Invoice_No;
		END IF;	
		RETURN NEW;	
	END IF;
	IF (TG_OP = 'UPDATE') THEN
		IF (NEW.Results = 'PASSED') THEN
			UPDATE Warehouse SET UT_Q_A = 'A' WHERE Material_ID = NEW.Material_ID AND Invoice_No = NEW.Invoice_No;
		ELSE
			UPDATE Warehouse SET UT_Q_A = 'Q' WHERE Material_ID = NEW.Material_ID AND Invoice_No = NEW.Invoice_No;
		END IF;	
		RETURN NEW;	
	END IF;	
	IF (TG_OP = 'DELETE') THEN
		UPDATE Warehouse SET UT_Q_A = 'UT' WHERE Material_ID = OLD.Material_ID AND Invoice_No = OLD.Invoice_No;
		RETURN OLD;	
	END IF;
	RETURN NULL;
END;
$body$ LANGUAGE 'plpgsql';

CREATE TRIGGER material_qc
AFTER INSERT OR UPDATE OR DELETE ON Material_Quality_Check
	FOR EACH ROW EXECUTE PROCEDURE rmqc();

CREATE FUNCTION pqc_date()
RETURNS TRIGGER AS $body$
DECLARE
	mfgdate DATE;
BEGIN
	IF (TG_OP = 'INSERT' OR TG_OP = 'UPDATE') THEN
		SELECT Mfg_Date INTO mfgdate FROM Batch WHERE Batch_No = NEW.Batch_No;
		IF( NEW.Analysis_Date < mfgdate) THEN
			RAISE EXCEPTION 'Analysis Date should be same as % or after it',mfgdate;
		END IF;			
		RETURN NEW;	
	END IF;
	RETURN NULL;
END;
$body$ LANGUAGE 'plpgsql';

CREATE TRIGGER product_qc_date
BEFORE INSERT OR UPDATE ON Product_Quality_Check
	FOR EACH ROW EXECUTE PROCEDURE pqc_date();

CREATE FUNCTION pqc()
RETURNS TRIGGER AS $body$
DECLARE
	flag VARCHAR(2);
	iterator RECORD;
BEGIN
	 
	IF (TG_OP = 'INSERT') THEN
		SELECT UT_Q_A INTO FLAG FROM Batch WHERE Batch_No = NEW.Batch_No;
		IF (flag = 'UT' OR flag = 'A') THEN
			IF (NEW.Results = 'PASSED') THEN
				UPDATE Batch SET UT_Q_A = 'A' WHERE Batch_No = NEW.Batch_No;
			ELSE
				UPDATE Batch SET UT_Q_A = 'Q' WHERE Batch_No = NEW.Batch_No;
			END IF;	
		END IF;
		RETURN NEW;	
	END IF;
	IF (TG_OP = 'UPDATE') THEN
		SELECT UT_Q_A INTO FLAG FROM Batch WHERE Batch_No = NEW.Batch_No;
		IF (flag = 'UT' OR flag = 'A') THEN
			IF (NEW.Results = 'PASSED') THEN
				UPDATE Batch SET UT_Q_A = 'A' WHERE Batch_No = NEW.Batch_No;
			ELSE
				UPDATE Batch SET UT_Q_A = 'Q' WHERE Batch_No = NEW.Batch_No;
			END IF;	
		END IF;
		RETURN NEW;	
	END IF;	
	IF (TG_OP = 'DELETE') THEN
		flag = '0';
		FOR iterator in (SELECT * FROM Product_Quality_Check WHERE Batch_NO = OLD.Batch_No) LOOP
		IF (iterator.Results = 'PASSED') THEN
			flag = '1';
		ELSE
			flag = '2';
			EXIT;
		END IF;
		END LOOP;
		IF (Flag = '0') THEN
			UPDATE Batch SET UT_Q_A = 'UT' WHERE Batch_No = OLD.Batch_No;
		ELSIF (Flag = '1') THEN
			UPDATE Batch SET UT_Q_A = 'A' WHERE Batch_No = OLD.Batch_No;
		ELSE 
			UPDATE Batch SET UT_Q_A = 'Q' WHERE Batch_No = OLD.Batch_No;
		END IF;
		RETURN OLD;	
	END IF;
	RETURN NULL;
END;
$body$ LANGUAGE 'plpgsql';

CREATE TRIGGER product_qc
AFTER INSERT OR UPDATE OR DELETE ON Product_Quality_Check
	FOR EACH ROW EXECUTE PROCEDURE pqc();
												
CREATE FUNCTION rmtransactions_tally()
RETURNS VOID AS $body$
DECLARE
	iterator1 RECORD;
	iterator2 RECORD;
	sum NUMERIC(10,2);
BEGIN
	FOR iterator1 IN (SELECT * FROM Transactions WHERE Transaction_Type = 'buy') LOOP
		sum := 0;
		FOR iterator2 IN (SELECT * FROM Transactions NATURAL JOIN Warehouse WHERE Invoice_No = iterator1.Invoice_No) LOOP
			sum := sum + iterator2.Val;
		END LOOP;
		IF (sum != iterator1.Total_Value) THEN
			RAISE NOTICE 'Issue with Invoice_No %',iterator1.Invoice_No;
		END IF;
	END LOOP;
END;
$body$ LANGUAGE 'plpgsql';