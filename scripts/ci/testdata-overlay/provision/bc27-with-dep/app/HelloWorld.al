// Minimal AL file for provision test fixture
// This file ensures the app directory contains valid AL code

codeunit 50000 "Test Codeunit"
{
    procedure HelloWorld()
    begin
        Message('Hello from AL Build Tools provision test');
    end;
}
