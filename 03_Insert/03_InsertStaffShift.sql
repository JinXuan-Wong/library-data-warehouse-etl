--Staff (No dependencies)
INSERT INTO Staff VALUES ('S001', 'Ahmad Zulkarnain', 'ahmadzulkarnain@gmail.com', '012-3456781', 'manager');

INSERT INTO Staff VALUES ('S002', 'Tan Mei Ling', 'tanmeiling@yahoo.com', '013-4567892', 'assistant');

INSERT INTO Staff VALUES ('S003', 'Ravi Kumar', 'ravikumar@outlook.com', '014-5678903', 'assistant');

INSERT INTO Staff VALUES ('S004', 'Siti Aisyah', 'siti_aisyah@gmail.com', '015-6789014', 'librarian');

INSERT INTO Staff VALUES ('S005', 'John Lim', 'johnlim@hotmail.com', '016-7890125', 'librarian');

INSERT INTO Staff VALUES ('S006', 'Farah Nadia', 'farahnadia@gmail.com', '017-8901236', 'librarian');

INSERT INTO Staff VALUES ('S007', 'Mohd Hafiz', 'mohdhafiz@yahoo.com', '018-9012347', 'librarian');

INSERT INTO Staff VALUES ('S008', 'Chong Wei', 'chongwei@outlook.com', '019-0123458', 'security');

INSERT INTO Staff VALUES ('S009', 'Lim Wai Kit', 'limwaikit@hotmail.com', '012-2345679', 'security');

INSERT INTO Staff VALUES ('S010', 'Nurul Ain', 'nurulain@gmail.com', '011-1234569', 'cleaner');

INSERT INTO Staff VALUES ('S011', 'Kumar Raj', 'kumarraj@hotmail.com', '012-2345670', 'cleaner');

--Shift (No dependencies)  
INSERT INTO Shift VALUES ('SH01', 'Librarians Morning', TO_TIMESTAMP('09:00:00', 'HH24:MI:SS'), TO_TIMESTAMP('15:30:00', 'HH24:MI:SS'));

INSERT INTO Shift VALUES ('SH02', 'Librarians Evening', TO_TIMESTAMP('15:30:00', 'HH24:MI:SS'), TO_TIMESTAMP('22:00:00', 'HH24:MI:SS'));

INSERT INTO Shift VALUES ('SH03', 'Librarians FullDay', TO_TIMESTAMP('09:00:00', 'HH24:MI:SS'), TO_TIMESTAMP('22:00:00', 'HH24:MI:SS'));

INSERT INTO Shift VALUES ('SH04', 'Assistants Morning', TO_TIMESTAMP('09:00:00', 'HH24:MI:SS'), TO_TIMESTAMP('15:30:00', 'HH24:MI:SS'));

INSERT INTO Shift VALUES ('SH05', 'Assistants Evening', TO_TIMESTAMP('15:30:00', 'HH24:MI:SS'), TO_TIMESTAMP('22:00:00', 'HH24:MI:SS'));

INSERT INTO Shift VALUES ('SH06', 'Assistants FullDay', TO_TIMESTAMP('09:00:00', 'HH24:MI:SS'), TO_TIMESTAMP('22:00:00', 'HH24:MI:SS'));

INSERT INTO Shift VALUES ('SH07', 'Manager Duty', TO_TIMESTAMP('09:00:00', 'HH24:MI:SS'), TO_TIMESTAMP('17:00:00', 'HH24:MI:SS'));

INSERT INTO Shift VALUES ('SH08', 'Security Morning', TO_TIMESTAMP('09:00:00', 'HH24:MI:SS'), TO_TIMESTAMP('15:30:00', 'HH24:MI:SS'));

INSERT INTO Shift VALUES ('SH09', 'Security Evening', TO_TIMESTAMP('15:30:00', 'HH24:MI:SS'), TO_TIMESTAMP('22:00:00', 'HH24:MI:SS'));

INSERT INTO Shift VALUES ('SH10', 'Cleaner afternoon', TO_TIMESTAMP('12:00:00', 'HH24:MI:SS'), TO_TIMESTAMP('14:00:00', 'HH24:MI:SS'));

INSERT INTO Shift VALUES ('SH11', 'Cleaner Night', TO_TIMESTAMP('20:00:00', 'HH24:MI:SS'), TO_TIMESTAMP('22:00:00', 'HH24:MI:SS'));

COMMIT;