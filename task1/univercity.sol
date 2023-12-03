pragma solidity >=0.6.0;

contract University {

    struct Student {
        string name;
        uint age;
        uint groupId;
    }

    struct Group {
        string name;
        uint[] studentIds;
    }

    Student[] public students;
    Group[] public groups;

    function createGroup(string memory _name) public {
        groups.push(Group(_name, new uint[](0)));
    }

    function enrollStudent(string memory _name, uint _age) public {
        uint groupId = uint(keccak256(abi.encodePacked(block.timestamp))) % groups.length;
        students.push(Student(_name, _age, groupId));
        groups[groupId].studentIds.push(students.length - 1);
    }

}
